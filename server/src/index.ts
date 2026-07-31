import { run, UpstreamError, type AgentEvent, type Usage } from './agent';
import { PLAN_SYSTEM_PROMPT } from './plan_prompt';
import { REVISE_SYSTEM_PROMPT } from './revise_prompt';
import { checkBundle } from './exercise_spec';
import { listPrograms, loadProgram, storeExercises, storeProgram } from './pool';

/**
 * LevelUp-API.
 *
 * Steht zwischen App und Anthropic, damit der Schlüssel des Betreibers nie auf
 * ein fremdes Gerät gelangt. Sie hält vier Dinge fest, die die App nicht
 * bestimmen darf: den System-Prompt, die Antwortlänge, das Kontingent und den
 * geteilten Pool.
 *
 * Es gibt keine Anmeldung — ein Gerät registriert sich einmal und bekommt ein
 * Token. Der Platz für ein späteres Konto ist im Schema vorgesehen
 * (`devices.user_id`).
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
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(token),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
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

async function authenticate(
  request: Request,
  env: Env,
): Promise<DeviceRow | null> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const tokenHash = await hashToken(header.slice(7).trim());

  return await env.DB.prepare(
    'SELECT id, user_id FROM devices WHERE token_hash = ?',
  )
    .bind(tokenHash)
    .first<DeviceRow>();
}

interface Quota {
  used: number;
  free: number;
  today: number;
  dailyLimit: number;
}

async function quotaFor(deviceId: string, env: Env): Promise<Quota> {
  const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
  // Fehlgeschlagene Läufe zählen nicht gegen das Kontingent — wer nichts
  // bekommen hat, soll nichts verbrauchen.
  const row = await env.DB.prepare(
    `SELECT
       COUNT(*) AS used,
       COALESCE(SUM(CASE WHEN created_at > ? THEN 1 ELSE 0 END), 0) AS today
     FROM generations
     WHERE device_id = ? AND status != 'failed'`,
  )
    .bind(dayAgo, deviceId)
    .first<{ used: number; today: number }>();

  return {
    used: row?.used ?? 0,
    free: Number(env.FREE_GENERATIONS),
    today: row?.today ?? 0,
    dailyLimit: Number(env.DAILY_LIMIT),
  };
}

/** Gibt die Antwort zurück, wenn das Kontingent den Lauf verbietet. */
async function quotaBlock(
  deviceId: string,
  env: Env,
): Promise<Response | null> {
  const quota = await quotaFor(deviceId, env);
  if (quota.today >= quota.dailyLimit) {
    return fail('Tageslimit erreicht. Morgen geht es weiter.', 429, 'daily_limit');
  }
  if (quota.used >= quota.free) {
    return fail('Freikontingent aufgebraucht.', 402, 'quota_exhausted');
  }
  return null;
}

// --- Endpunkte -------------------------------------------------------------

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

  return json({
    deviceId: id,
    token,
    freeGenerations: Number(env.FREE_GENERATIONS),
  });
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

// --- Erzeugen und Überarbeiten ---------------------------------------------

/**
 * Schneidet das JSON-Objekt aus der Antwort.
 *
 * Trotz Anweisung kommt gelegentlich ein Code-Zaun oder ein einleitender Satz
 * mit. Daran zu scheitern wäre albern, wenn das Dokument daneben steht.
 */
function extractJson(text: string): Record<string, unknown> | null {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const decoded = JSON.parse(text.slice(start, end + 1)) as unknown;
    return typeof decoded === 'object' && decoded !== null
      ? (decoded as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

/**
 * Öffnet den Ereignisstrom zur App und lässt den Lauf dahinter arbeiten.
 *
 * Die App bekommt ein eigenes, kleines Protokoll statt Anthropics Rohformat:
 * `thinking`, `search`, `writing`, dann genau ein `done` oder `error`. Der
 * fertige Plan wird als Ganzes geschickt, nicht häppchenweise — er muss hier
 * ohnehin geprüft werden, bevor ihn ein Gerät sieht.
 */
function streamRun(
  env: Env,
  ctx: ExecutionContext,
  generationId: string,
  system: string,
  message: unknown,
  withTools: boolean,
  finish: (document: Record<string, unknown>, reused: string[]) => unknown,
  validate?: (text: string) => string[],
): Response {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  // Die Schreibvorgänge müssen sich reihen — `emit` wird synchron aufgerufen,
  // das Schreiben ist es nicht.
  let queue = Promise.resolve();
  const send = (payload: unknown): void => {
    queue = queue
      .then(() => writer.write(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`)))
      .catch(() => {
        // Gerät ist weg. Der Lauf darf trotzdem sauber zu Ende gehen, damit
        // der Verbrauch gebucht wird.
      });
  };

  ctx.waitUntil(
    (async () => {
      let usage: Usage | null = null;
      let status = 'failed';
      try {
        const result = await run(
          env,
          system,
          message,
          (event: AgentEvent) => send(event),
          withTools,
          validate,
        );
        usage = result.usage;

        if (result.stopReason === 'refusal') {
          send({
            type: 'error',
            code: 'refused',
            message: 'Die Anfrage wurde abgelehnt. Formulier sie anders.',
          });
        } else if (result.stopReason === 'max_tokens') {
          send({
            type: 'error',
            code: 'too_long',
            message:
              'Die Antwort wurde abgeschnitten. Bitte um weniger — kürzere ' +
              'Laufzeit oder weniger Phasen.',
          });
        } else {
          const document = extractJson(result.text);
          if (document === null) {
            send({
              type: 'error',
              code: 'unreadable',
              message: 'Die Antwort ließ sich nicht lesen. Bitte nochmal.',
            });
          } else {
            const payload = finish(document, result.reused);
            if (payload === null) {
              send({
                type: 'error',
                code: 'not_a_plan',
                message:
                  'Daraus ließ sich kein Übungsplan machen. Beschreib eine ' +
                  'Fähigkeit, die du üben willst.',
              });
            } else {
              send(payload);
              status = 'done';
            }
          }
        }
      } catch (error) {
        logError('run', error);
        send({
          type: 'error',
          code: error instanceof UpstreamError ? 'upstream' : 'internal',
          message: 'Der Planer ist gerade nicht erreichbar. Bitte später nochmal.',
        });
      } finally {
        await queue;
        await writer.close().catch(() => undefined);
        await record(env, generationId, usage, status);
      }
    })(),
  );

  return new Response(readable, {
    headers: {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      ...CORS,
    },
  });
}

async function record(
  env: Env,
  generationId: string,
  usage: Usage | null,
  status: string,
): Promise<void> {
  try {
    await env.DB.prepare(
      `UPDATE generations
         SET input_tokens = ?, output_tokens = ?, cache_read = ?,
             cache_write = ?, status = ?, stop_reason = ?
       WHERE id = ?`,
    )
      .bind(
        usage?.input ?? 0,
        usage?.output ?? 0,
        usage?.cacheRead ?? 0,
        usage?.cacheWrite ?? 0,
        status,
        usage?.stopReason ?? null,
        generationId,
      )
      .run();
  } catch (error) {
    logError('record-usage', error);
  }
}

async function openGeneration(
  env: Env,
  deviceId: string,
  kind: string,
): Promise<string> {
  const id = `gen_${randomToken().slice(0, 24)}`;
  await env.DB.prepare(
    `INSERT INTO generations (id, device_id, created_at, kind)
     VALUES (?, ?, ?, ?)`,
  )
    .bind(id, deviceId, Date.now(), kind)
    .run();
  return id;
}

async function generate(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  device: DeviceRow,
): Promise<Response> {
  let prompt = '';
  try {
    const body = (await request.json()) as { request?: unknown };
    if (typeof body.request === 'string') prompt = body.request.trim();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (prompt.length === 0) {
    return fail('Beschreib, worum es gehen soll.', 400, 'empty_request');
  }
  if (prompt.length > Number(env.MAX_REQUEST_CHARS)) {
    return fail(
      `Die Beschreibung ist zu lang (max. ${env.MAX_REQUEST_CHARS} Zeichen).`,
      400,
      'request_too_long',
    );
  }

  const blocked = await quotaBlock(device.id, env);
  if (blocked !== null) return blocked;

  const generationId = await openGeneration(env, device.id, 'plan');

  return streamRun(
    env,
    ctx,
    generationId,
    PLAN_SYSTEM_PROMPT,
    prompt,
    true,
    (document, reused) => {
      const programs = document.programs;
      // Ein leeres Bundle ist die Absage des Modells an Themenfremdes — kein
      // Formatfehler, und es soll auch nicht als solcher gemeldet werden.
      if (!Array.isArray(programs) || programs.length === 0) return null;
      return { type: 'done', bundle: document, reused };
    },
    // Die Übung ist der Baustein, aus dem alles andere besteht. Ein schlechter
    // Plan wird weggeworfen; eine schlechte Übung landet im Pool und wird von
    // da an weiterverwendet. Deshalb wird sie geprüft, nicht nur erbeten.
    (text) => {
      const document = extractJson(text);
      return document === null ? [] : checkBundle(document);
    },
  );
}

const MAX_BUNDLE_CHARS = 200_000;

async function revise(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  device: DeviceRow,
): Promise<Response> {
  let bundle: unknown = null;
  let feedback = '';
  try {
    const body = (await request.json()) as {
      bundle?: unknown;
      feedback?: unknown;
    };
    bundle = body.bundle ?? null;
    if (typeof body.feedback === 'string') feedback = body.feedback.trim();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (feedback.length === 0) {
    return fail('Sag, was nicht passt.', 400, 'empty_request');
  }
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
  const clean = { ...(bundle as Record<string, unknown>) };
  delete clean.personalNote;

  const planText = JSON.stringify(clean);
  if (planText.length > MAX_BUNDLE_CHARS) {
    return fail('Der Plan ist zu groß.', 400, 'bundle_too_large');
  }

  const blocked = await quotaBlock(device.id, env);
  if (blocked !== null) return blocked;

  const generationId = await openGeneration(env, device.id, 'revision');

  const message = `DER PLAN:\n${planText}\n\nRÜCKMELDUNG:\n${feedback}`;

  return streamRun(
    env,
    ctx,
    generationId,
    REVISE_SYSTEM_PROMPT,
    message,
    false,
    (document) => {
      const operations = document.operations;
      if (!Array.isArray(operations)) return null;
      return { type: 'done', patch: document };
    },
  );
}

// --- Annehmen ---------------------------------------------------------------

/** Grobe Plausibilität, bevor etwas in die geteilte Bibliothek wandert. */
function looksLikeExercise(raw: unknown): boolean {
  if (typeof raw !== 'object' || raw === null) return false;
  const ex = raw as Record<string, unknown>;
  return (
    typeof ex.id === 'string' &&
    ex.id.length > 1 &&
    ex.id.length < 120 &&
    typeof ex.name === 'string' &&
    ex.name.trim().length > 1 &&
    ex.name.length < 200 &&
    JSON.stringify(raw).length < 20_000
  );
}

/**
 * Ein Plan, den jemand behalten hat, geht in den Pool.
 *
 * Erst hier, nicht schon beim Erzeugen: was weggeworfen wurde, soll niemand
 * als Vorlage bekommen. Der persönliche Teil bleibt auf dem Gerät.
 */
async function accept(
  request: Request,
  env: Env,
  device: DeviceRow,
): Promise<Response> {
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

  // Was in den Pool geht, ist ausdrücklich ohne den persönlichen Teil.
  const shared = { ...bundle };
  delete shared.personalNote;

  const exercises = Array.isArray(shared.exercises)
    ? shared.exercises.filter(looksLikeExercise)
    : [];

  try {
    const stored = await storeExercises(env, exercises, device.id);
    const ok = await storeProgram(env, shared, device.id);
    return json({ ok, exercises: stored });
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
 * steht, ist ohnehin das, was Leute ausdrücklich zum Teilen freigegeben haben.
 */
async function library(url: URL, env: Env): Promise<Response> {
  const id = url.pathname.slice('/v1/library/'.length);

  if (id.length === 0) {
    const programs = await listPrograms(env);
    // Dieselbe Hülle wie der frühere statische Katalog, damit ältere
    // App-Versionen nicht daran ersticken.
    return json({ version: 1, programs });
  }

  const bundle = await loadProgram(env, id);
  if (bundle === null) return fail('Kein Plan mit dieser Kennung.', 404, 'not_found');
  return json(bundle);
}

// --- Einstieg --------------------------------------------------------------

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
        if (request.method !== 'GET') {
          return fail('Nur GET.', 405, 'method_not_allowed');
        }
        return await library(url, env);
      }

      const routes = ['/v1/me', '/v1/generate', '/v1/revise', '/v1/plans/accept'];
      if (!routes.includes(url.pathname)) {
        return fail('Unbekannter Endpunkt.', 404, 'not_found');
      }

      const device = await authenticate(request, env);
      if (device === null) {
        return fail('Nicht angemeldet.', 401, 'unauthenticated');
      }

      if (url.pathname === '/v1/me') return await me(device, env);

      if (request.method !== 'POST') {
        return fail('Nur POST.', 405, 'method_not_allowed');
      }

      switch (url.pathname) {
        case '/v1/generate':
          return await generate(request, env, ctx, device);
        case '/v1/revise':
          return await revise(request, env, ctx, device);
        default:
          return await accept(request, env, device);
      }
    } catch (error) {
      logError(url.pathname, error);
      return fail('Unerwarteter Fehler.', 500, 'internal');
    }
  },
} satisfies ExportedHandler<Env>;
