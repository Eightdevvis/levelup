import { SchemaError, UpstreamError, addiere, leererVerbrauch, type Verbrauch } from './anthropic';
import { baueBundle } from './bundle';
import type { Ereignis, Melder } from './ereignisse';
import {
  erstelleLauf,
  ladeLauf,
  ladeTaetigkeiten,
  merkeArchitektur,
  merkeDiagnose,
  schliesseLauf,
  schreibeKennzahlen,
} from './laeufe';
import { ladeUebungen } from './bibliothek';
import { pruefeGrundstock, spieleEin } from './grundstock';
import { fuehreAus } from './pipeline';
import { pruefeEingabe } from './pruefen';
import { diagnostiziere } from './prompts/diagnose';
import { planeStruktur } from './prompts/architekt';
import { REVISE_SYSTEM_PROMPT } from './revise_prompt';
import { frage } from './anthropic';
import { listPrograms, loadProgram, storeProgram } from './pool';
import type { Eingabe, Rueckfrageantwort } from './typen';

/**
 * LevelUp-API.
 *
 * Steht zwischen App und Anthropic, damit der Schlüssel des Betreibers nie auf
 * ein fremdes Gerät gelangt. Sie hält vier Dinge fest, die die App nicht
 * bestimmen darf: die Prompts, die Antwortlänge, das Kontingent und die
 * geteilte Bibliothek.
 *
 * Ein Lauf zieht sich über drei Anfragen — Diagnose, Rückfragen, Plan. Der
 * Zustand dazwischen liegt auf dem Server, nicht in der App: sonst wäre das
 * Problemmodell Nutzereingabe.
 */

// --- kleine Helfer ---------------------------------------------------------

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization,content-type',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...CORS },
  });
}

function fail(message: string, status: number, code?: string): Response {
  return json({ error: { message, code } }, status);
}

/** Zufall aus der Web-Crypto — nie `Math.random()` für etwas, das schützt. */
function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Gespeichert wird nur der Hash. Wer die Datenbank liest, kann sich damit
 * nicht als fremdes Gerät ausgeben — und die Suche läuft über einen
 * Index-Treffer statt über einen Zeichenvergleich, was zeitbasierte
 * Rückschlüsse ausschließt.
 */
async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function logError(where: string, error: unknown): void {
  console.error(
    JSON.stringify({
      message: 'request failed',
      where,
      error: error instanceof Error ? error.message : String(error),
    }),
  );
}

interface DeviceRow {
  id: string;
  user_id: string | null;
}

async function authenticate(request: Request, env: Env): Promise<DeviceRow | null> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const tokenHash = await hashToken(header.slice(7).trim());

  return await env.DB.prepare('SELECT id, user_id FROM devices WHERE token_hash = ?')
    .bind(tokenHash)
    .first<DeviceRow>();
}

/**
 * Der Betreiberzugang für Prüfliste, Kennzahlen und Grundstock.
 *
 * Verglichen wird über die Hashes, nicht über die Zeichen: ein Vergleich, der
 * beim ersten Unterschied abbricht, verrät die Länge des gemeinsamen Anfangs.
 */
async function istBetreiber(request: Request, env: Env): Promise<boolean> {
  const erwartet = env.BETREIBER_TOKEN;
  if (typeof erwartet !== 'string' || erwartet.length === 0) return false;

  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return false;

  const a = new TextEncoder().encode(await hashToken(header.slice(7).trim()));
  const b = new TextEncoder().encode(await hashToken(erwartet));
  return a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b);
}

interface Quota {
  used: number;
  free: number;
  today: number;
  dailyLimit: number;
}

/**
 * Eine Zeile in `generations` je Lauf, nicht je KI-Aufruf — sonst verbraucht
 * ein Lauf mit fünfzehn Bedarfen siebzehn Generierungen.
 *
 * `diagnose` zählt noch nicht: wer eine Diagnose bekommen und keinen Plan
 * abgerufen hat, hat nichts erhalten, was ein Kontingent kosten dürfte.
 */
const ZAEHLT_NICHT = ['failed', 'diagnose'];

async function quotaFor(deviceId: string, env: Env): Promise<Quota> {
  const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
  const platzhalter = ZAEHLT_NICHT.map(() => '?').join(', ');
  const row = await env.DB.prepare(
    `SELECT
       COUNT(*) AS used,
       COALESCE(SUM(CASE WHEN created_at > ? THEN 1 ELSE 0 END), 0) AS today
     FROM generations
     WHERE device_id = ? AND status NOT IN (${platzhalter})`,
  )
    .bind(dayAgo, deviceId, ...ZAEHLT_NICHT)
    .first<{ used: number; today: number }>();

  return {
    used: row?.used ?? 0,
    free: Number(env.FREE_GENERATIONS),
    today: row?.today ?? 0,
    dailyLimit: Number(env.DAILY_LIMIT),
  };
}

/** Gibt die Antwort zurück, wenn das Kontingent den Lauf verbietet. */
async function quotaBlock(deviceId: string, env: Env): Promise<Response | null> {
  const quota = await quotaFor(deviceId, env);
  if (quota.today >= quota.dailyLimit) {
    return fail('Tageslimit erreicht. Morgen geht es weiter.', 429, 'daily_limit');
  }
  if (quota.used >= quota.free) {
    return fail('Freikontingent aufgebraucht.', 402, 'quota_exhausted');
  }
  return null;
}

async function record(
  env: Env,
  generationId: string,
  verbrauch: Verbrauch,
  status: string,
): Promise<void> {
  try {
    await env.DB.prepare(
      `UPDATE generations
         SET input_tokens = ?, output_tokens = ?, cache_read = ?,
             cache_write = ?, status = ?
       WHERE id = ?`,
    )
      .bind(
        verbrauch.input,
        verbrauch.output,
        verbrauch.cacheRead,
        verbrauch.cacheWrite,
        status,
        generationId,
      )
      .run();
  } catch (error) {
    logError('record-usage', error);
  }
}

async function openGeneration(env: Env, deviceId: string, kind: string): Promise<string> {
  const id = `gen_${randomToken().slice(0, 24)}`;
  await env.DB.prepare(
    `INSERT INTO generations (id, device_id, created_at, kind, status)
     VALUES (?, ?, ?, ?, 'diagnose')`,
  )
    .bind(id, deviceId, Date.now(), kind)
    .run();
  return id;
}

// --- Gerät -----------------------------------------------------------------

/** Einmalige Registrierung. Gibt das einzige Mal ein Token im Klartext aus. */
async function registerDevice(request: Request, env: Env): Promise<Response> {
  let platform = 'unknown';
  try {
    const body = (await request.json()) as { platform?: unknown };
    if (typeof body.platform === 'string') platform = body.platform.slice(0, 32);
  } catch {
    // Rumpf ist optional — Plattform bleibt unbekannt.
  }

  const token = randomToken();
  const id = `dev_${randomToken().slice(0, 24)}`;
  const now = Date.now();

  await env.DB.prepare(
    `INSERT INTO devices (id, token_hash, platform, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(id, await hashToken(token), platform, now, now)
    .run();

  return json({ deviceId: id, token, freeGenerations: Number(env.FREE_GENERATIONS) });
}

async function me(device: DeviceRow, env: Env): Promise<Response> {
  const quota = await quotaFor(device.id, env);
  return json({
    deviceId: device.id,
    linkedAccount: device.user_id !== null,
    used: quota.used,
    remaining: Math.max(0, quota.free - quota.used),
    dailyRemaining: Math.max(0, quota.dailyLimit - quota.today),
  });
}

// --- [1] Diagnose ----------------------------------------------------------

async function starteLauf(
  request: Request,
  env: Env,
  device: DeviceRow,
): Promise<Response> {
  let roh: unknown;
  try {
    roh = await request.json();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  const geprueft = pruefeEingabe(roh, Number(env.MAX_REQUEST_CHARS));
  if (!geprueft.ok) {
    return json({ error: { message: 'Die Eingabe passt nicht.', code: 'bad_input', details: geprueft.fehler } }, 400);
  }

  const blocked = await quotaBlock(device.id, env);
  if (blocked !== null) return blocked;

  const generationId = await openGeneration(env, device.id, 'lauf');
  const laufId = `lauf_${randomToken().slice(0, 24)}`;
  await erstelleLauf(env, { id: laufId, deviceId: device.id, eingabe: geprueft.wert, generationId });

  return await fuehreDiagnoseAus(env, laufId, generationId, geprueft.wert, []);
}

async function beantworteRueckfragen(
  request: Request,
  env: Env,
  device: DeviceRow,
  laufId: string,
): Promise<Response> {
  const lauf = await ladeLauf(env, laufId, device.id);
  if (lauf === null) return fail('Kein Lauf mit dieser Kennung.', 404, 'not_found');
  if (lauf.status !== 'rueckfragen') {
    return fail('Für diesen Lauf stehen keine Fragen offen.', 409, 'wrong_state');
  }

  let antworten: (string | null)[] = [];
  try {
    const body = (await request.json()) as { antworten?: unknown };
    if (Array.isArray(body.antworten)) {
      antworten = body.antworten.map((a) =>
        typeof a === 'string' && a.trim().length > 0
          ? a.trim().slice(0, Number(env.MAX_REQUEST_CHARS))
          : null,
      );
    }
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  // Die Fragen kommen aus dem Lauf, nicht aus der Anfrage. Sonst könnte ein
  // Gerät sich seine eigenen Fragen ausdenken und beantworten.
  const paare: Rueckfrageantwort[] = lauf.rueckfragen.map((frageText, i) => ({
    frage: frageText,
    antwort: antworten[i] ?? null,
  }));

  return await fuehreDiagnoseAus(
    env,
    lauf.id,
    lauf.generation_id ?? '',
    lauf.eingabe,
    paare,
  );
}

async function fuehreDiagnoseAus(
  env: Env,
  laufId: string,
  generationId: string,
  eingabe: Eingabe,
  antworten: Rueckfrageantwort[],
): Promise<Response> {
  try {
    const { wert, verbrauch } = await diagnostiziere(env, { eingabe, antworten });
    await merkeDiagnose(env, laufId, wert);
    await record(env, generationId, verbrauch, 'diagnose');

    return json({
      lauf_id: laufId,
      problemmodell: wert,
      rueckfragen: wert.rueckfragen,
    });
  } catch (error) {
    logError('diagnose', error);
    await record(env, generationId, leererVerbrauch(), 'failed');
    return fail(fehlertext(error), fehlerstatus(error), fehlercode(error));
  }
}

function fehlercode(error: unknown): string {
  if (error instanceof SchemaError) return 'unreadable';
  if (error instanceof UpstreamError) return 'upstream';
  return 'internal';
}

function fehlerstatus(error: unknown): number {
  return error instanceof UpstreamError ? 502 : 500;
}

function fehlertext(error: unknown): string {
  if (error instanceof SchemaError) {
    return 'Die Antwort ließ sich nicht lesen. Bitte nochmal.';
  }
  return 'Der Planer ist gerade nicht erreichbar. Bitte später nochmal.';
}

// --- [2] bis [5]: der Plan als Ereignisstrom -------------------------------

/**
 * Öffnet den Ereignisstrom zur App und lässt die Pipeline dahinter arbeiten.
 *
 * Die App bekommt ein eigenes, kleines Protokoll statt Anthropics Rohformat.
 * Der fertige Plan geht als Ganzes hinaus, nicht häppchenweise — er muss hier
 * ohnehin geprüft werden, bevor ihn ein Gerät sieht.
 */
async function planeLauf(
  env: Env,
  ctx: ExecutionContext,
  device: DeviceRow,
  laufId: string,
): Promise<Response> {
  const lauf = await ladeLauf(env, laufId, device.id);
  if (lauf === null) return fail('Kein Lauf mit dieser Kennung.', 404, 'not_found');
  if (lauf.problemmodell === null) {
    return fail('Für diesen Lauf gibt es noch keine Diagnose.', 409, 'wrong_state');
  }
  if (lauf.status === 'fertig') {
    return fail('Dieser Lauf ist bereits abgeschlossen.', 409, 'wrong_state');
  }

  const blocked = await quotaBlock(device.id, env);
  if (blocked !== null) return blocked;

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  // Die Schreibvorgänge müssen sich reihen — `melde` wird synchron aufgerufen,
  // das Schreiben ist es nicht.
  let schlange = Promise.resolve();
  const sende = (payload: unknown): void => {
    schlange = schlange
      .then(() => writer.write(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`)))
      .catch(() => {
        // Gerät ist weg. Der Lauf darf trotzdem sauber zu Ende gehen, damit
        // der Verbrauch gebucht wird und die neuen Bausteine erhalten bleiben.
      });
  };
  const melde: Melder = (ereignis: Ereignis) => sende(ereignis);

  const generationId = lauf.generation_id ?? (await openGeneration(env, device.id, 'lauf'));
  const problemmodell = lauf.problemmodell;

  ctx.waitUntil(
    (async () => {
      const verbrauch = leererVerbrauch();
      let status = 'failed';
      try {
        melde({ type: 'schritt', name: 'architekt' });
        const plan = await planeStruktur(env, {
          problemmodell,
          eingabe: lauf.eingabe,
          melde,
        });
        addiere(verbrauch, plan.verbrauch);
        await merkeArchitektur(env, lauf.id, plan.wert);

        const ergebnis = await fuehreAus(env, {
          eingabe: lauf.eingabe,
          problemmodell,
          architektur: plan.wert,
          laufId: lauf.id,
          deviceId: device.id,
          melde,
        });
        addiere(verbrauch, ergebnis.verbrauch);

        melde({ type: 'schritt', name: 'zusammenbau' });
        const ids = [...new Set([...ergebnis.referenzen.values()].map((r) => r.uebung_id))];
        const bundle = baueBundle({
          architektur: plan.wert,
          referenzen: ergebnis.referenzen,
          uebungen: await ladeUebungen(env, ids),
          problemmodell,
          eingabe: lauf.eingabe,
          programmId: `prog_${randomToken().slice(0, 24)}`,
          taetigkeiten: await ladeTaetigkeiten(env),
        });

        await schreibeKennzahlen(env, lauf.id, ergebnis.kennzahlen);
        await schliesseLauf(env, lauf.id, 'fertig', bundle.programs[0]?.id ?? null);

        sende({ type: 'done', bundle, kennzahlen: ergebnis.kennzahlen });
        status = 'done';
      } catch (error) {
        logError('plan', error);
        await schliesseLauf(env, lauf.id, 'fehlgeschlagen', null);
        sende({ type: 'error', code: fehlercode(error), message: fehlertext(error) });
      } finally {
        await schlange;
        await writer.close().catch(() => undefined);
        await record(env, generationId, verbrauch, status);
      }
    })(),
  );

  return new Response(readable, {
    headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', ...CORS },
  });
}

// --- Überarbeiten -----------------------------------------------------------

const MAX_BUNDLE_CHARS = 200_000;

/**
 * Ein Patch auf einen fertigen Plan. Läuft an der Pipeline vorbei: er ändert
 * das Programm, nicht die Bibliothek, und braucht deshalb weder Retrieval noch
 * Dedupe.
 */
async function revise(
  request: Request,
  env: Env,
  device: DeviceRow,
): Promise<Response> {
  let bundle: unknown = null;
  let feedback = '';
  try {
    const body = (await request.json()) as { bundle?: unknown; feedback?: unknown };
    bundle = body.bundle ?? null;
    if (typeof body.feedback === 'string') feedback = body.feedback.trim();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (feedback.length === 0) return fail('Sag, was nicht passt.', 400, 'empty_request');
  if (feedback.length > Number(env.MAX_REQUEST_CHARS)) {
    return fail(
      `Die Rückmeldung ist zu lang (max. ${env.MAX_REQUEST_CHARS} Zeichen).`,
      400,
      'request_too_long',
    );
  }
  if (typeof bundle !== 'object' || bundle === null) {
    return fail('Kein Plan mitgeschickt.', 400, 'missing_bundle');
  }

  // Der persönliche Teil geht nicht mit zurück — er ist Ausgabe, nicht
  // Eingabe, und würde die Überarbeitung nur auf sich selbst beziehen.
  const sauber = { ...(bundle as Record<string, unknown>) };
  delete sauber.personalNote;

  const planText = JSON.stringify(sauber);
  if (planText.length > MAX_BUNDLE_CHARS) {
    return fail('Der Plan ist zu groß.', 400, 'bundle_too_large');
  }

  const blocked = await quotaBlock(device.id, env);
  if (blocked !== null) return blocked;

  const generationId = await openGeneration(env, device.id, 'revision');

  try {
    const { wert, verbrauch } = await frage<Record<string, unknown>>(env, {
      system: REVISE_SYSTEM_PROMPT,
      nachricht: `DER PLAN:\n${planText}\n\nRÜCKMELDUNG:\n${feedback}`,
      modell: env.MODELL_ARCHITEKT,
      maxTokens: Number(env.MAX_OUTPUT_TOKENS),
      pruefe: (roh) => {
        const o = roh as Record<string, unknown>;
        return Array.isArray(o?.operations)
          ? { ok: true, wert: o }
          : { ok: false, fehler: ['operations: fehlt oder ist keine Liste'] };
      },
    });

    await record(env, generationId, verbrauch, 'done');
    return json({ patch: wert });
  } catch (error) {
    logError('revise', error);
    await record(env, generationId, leererVerbrauch(), 'failed');
    return fail(fehlertext(error), fehlerstatus(error), fehlercode(error));
  }
}

// --- Annehmen ---------------------------------------------------------------

/**
 * Ein Plan, den jemand behalten hat, wird sichtbar.
 *
 * Die Übungen liegen längst in der Bibliothek — sie sind während des Laufs
 * entstanden, nicht erst hier. Was fehlt, ist das Programm: erst wenn jemand
 * es behält, soll es anderen als Vorlage begegnen.
 */
async function accept(request: Request, env: Env, device: DeviceRow): Promise<Response> {
  let bundle: Record<string, unknown>;
  try {
    const body = (await request.json()) as { bundle?: unknown };
    if (typeof body.bundle !== 'object' || body.bundle === null) {
      return fail('Kein Plan mitgeschickt.', 400, 'missing_bundle');
    }
    bundle = body.bundle as Record<string, unknown>;
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (JSON.stringify(bundle).length > MAX_BUNDLE_CHARS) {
    return fail('Der Plan ist zu groß.', 400, 'bundle_too_large');
  }

  const programs = bundle.programs;
  if (!Array.isArray(programs) || programs.length === 0) {
    return fail('Der Plan enthält kein Programm.', 400, 'empty_bundle');
  }

  // Was geteilt wird, ist ausdrücklich ohne den persönlichen Teil.
  const geteilt = { ...bundle };
  delete geteilt.personalNote;

  try {
    const ok = await storeProgram(env, geteilt, device.id);
    return json({ ok });
  } catch (error) {
    logError('accept', error);
    return fail('Konnte nicht gespeichert werden.', 500, 'internal');
  }
}

// --- Offene Bibliothek ------------------------------------------------------

/**
 * Lesend und ohne Anmeldung.
 *
 * Stöbern soll niemanden zwingen, sich vorher zu registrieren — und was hier
 * steht, ist ohnehin das, was Leute ausdrücklich behalten haben.
 */
async function library(url: URL, env: Env): Promise<Response> {
  const id = url.pathname.slice('/v1/library/'.length);

  if (id.length === 0) {
    const programs = await listPrograms(env);
    return json({ version: 1, programs });
  }

  const bundle = await loadProgram(env, id);
  if (bundle === null) return fail('Kein Plan mit dieser Kennung.', 404, 'not_found');
  return json(bundle);
}

// --- Betreiberansichten -----------------------------------------------------

/**
 * Die Prüfliste und die Kennzahlen.
 *
 * Ohne Ansicht staut sich die Prüfliste still auf, und niemand merkt, dass die
 * Schwelle falsch steht (§9). Deshalb sind beide Endpunkte da, bevor der erste
 * Eintrag entsteht.
 */
async function pruefliste(env: Env): Promise<Response> {
  const ergebnis = await env.DB.prepare(
    `SELECT p.id, p.created_at, p.lauf_id, p.kandidat, p.bestand_id, p.aehnlichkeit,
            u.titel AS bestand_titel, u.anleitung AS bestand_anleitung
       FROM pruefliste p
       LEFT JOIN uebungen u ON u.id = p.bestand_id
      WHERE p.status = 'offen'
      ORDER BY p.created_at DESC
      LIMIT 200`,
  ).all<Record<string, unknown>>();

  return json({
    eintraege: ergebnis.results.map((z) => ({
      ...z,
      kandidat: JSON.parse(String(z.kandidat)) as unknown,
    })),
  });
}

async function entscheidePruefliste(
  request: Request,
  env: Env,
  id: string,
): Promise<Response> {
  let status = '';
  try {
    const body = (await request.json()) as { status?: unknown };
    if (typeof body.status === 'string') status = body.status;
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (status !== 'eigenstaendig' && status !== 'verworfen') {
    return fail('Status muss "eigenstaendig" oder "verworfen" sein.', 400, 'bad_status');
  }

  await env.DB.prepare('UPDATE pruefliste SET status = ? WHERE id = ?').bind(status, id).run();
  return json({ ok: true });
}

async function kennzahlen(env: Env): Promise<Response> {
  const zeilen = await env.DB.prepare(
    `SELECT lauf_id, created_at, bedarfe, reuse, neu, neue_tags, pruefliste, uebungspositionen
       FROM lauf_kennzahlen ORDER BY created_at DESC LIMIT 200`,
  ).all<Record<string, number | string>>();

  interface Summe {
    bedarfe: number;
    reuse: number;
    neu: number;
    pruefliste: number;
  }

  const summe = zeilen.results.reduce<Summe>(
    (s, z) => ({
      bedarfe: s.bedarfe + Number(z.bedarfe),
      reuse: s.reuse + Number(z.reuse),
      neu: s.neu + Number(z.neu),
      pruefliste: s.pruefliste + Number(z.pruefliste),
    }),
    { bedarfe: 0, reuse: 0, neu: 0, pruefliste: 0 },
  );

  return json({
    laeufe: zeilen.results,
    // Die eine Zahl, auf die es ankommt: sie soll über die Zeit steigen.
    wiederverwendungsquote: summe.bedarfe === 0 ? null : summe.reuse / summe.bedarfe,
    summe,
  });
}

/** Kaltstart: eine Grundstockdatei einspielen. Läuft mehrfach ohne zu doppeln. */
async function grundstock(request: Request, env: Env): Promise<Response> {
  let roh: unknown;
  try {
    roh = await request.json();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  const geprueft = pruefeGrundstock(roh);
  if (Array.isArray(geprueft)) {
    return json({ error: { message: 'Der Grundstock passt nicht.', code: 'bad_input', details: geprueft } }, 400);
  }

  try {
    return json(await spieleEin(env, geprueft));
  } catch (error) {
    logError('grundstock', error);
    return fail('Konnte nicht eingespielt werden.', 500, 'internal');
  }
}

// --- Einstieg --------------------------------------------------------------

const LAUF_MUSTER = /^\/v1\/laeufe\/([A-Za-z0-9_-]{1,64})\/(antworten|plan)$/;
const PRUEF_MUSTER = /^\/v1\/pruefliste\/([A-Za-z0-9_-]{1,64})$/;

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    try {
      if (url.pathname === '/v1/devices' && request.method === 'POST') {
        return await registerDevice(request, env);
      }

      if (url.pathname.startsWith('/v1/library')) {
        if (request.method !== 'GET') return fail('Nur GET.', 405, 'method_not_allowed');
        return await library(url, env);
      }

      // Betreiberwege zuerst: sie hängen an einem anderen Token als die Geräte.
      if (url.pathname === '/v1/grundstock') {
        if (!(await istBetreiber(request, env))) {
          return fail('Nicht angemeldet.', 401, 'unauthenticated');
        }
        if (request.method !== 'POST') return fail('Nur POST.', 405, 'method_not_allowed');
        return await grundstock(request, env);
      }
      if (url.pathname === '/v1/pruefliste' || url.pathname === '/v1/kennzahlen') {
        if (!(await istBetreiber(request, env))) {
          return fail('Nicht angemeldet.', 401, 'unauthenticated');
        }
        return url.pathname === '/v1/pruefliste' ? await pruefliste(env) : await kennzahlen(env);
      }
      const pruefTreffer = PRUEF_MUSTER.exec(url.pathname);
      if (pruefTreffer !== null) {
        if (!(await istBetreiber(request, env))) {
          return fail('Nicht angemeldet.', 401, 'unauthenticated');
        }
        if (request.method !== 'POST') return fail('Nur POST.', 405, 'method_not_allowed');
        return await entscheidePruefliste(request, env, pruefTreffer[1]);
      }

      const device = await authenticate(request, env);
      if (device === null) return fail('Nicht angemeldet.', 401, 'unauthenticated');

      if (url.pathname === '/v1/me') return await me(device, env);

      if (request.method !== 'POST') return fail('Nur POST.', 405, 'method_not_allowed');

      const laufTreffer = LAUF_MUSTER.exec(url.pathname);
      if (laufTreffer !== null) {
        return laufTreffer[2] === 'antworten'
          ? await beantworteRueckfragen(request, env, device, laufTreffer[1])
          : await planeLauf(env, ctx, device, laufTreffer[1]);
      }

      switch (url.pathname) {
        case '/v1/laeufe':
          return await starteLauf(request, env, device);
        case '/v1/revise':
          return await revise(request, env, device);
        case '/v1/plans/accept':
          return await accept(request, env, device);
        default:
          return fail('Unbekannter Endpunkt.', 404, 'not_found');
      }
    } catch (error) {
      logError(url.pathname, error);
      return fail('Unerwarteter Fehler.', 500, 'internal');
    }
  },
} satisfies ExportedHandler<Env>;
