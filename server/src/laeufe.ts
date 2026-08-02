import type { Architektur, Eingabe, Kennzahlen, Lauf, LaufStatus, Problemmodell } from './typen';

/**
 * Der Lauf als Serverzustand.
 *
 * Ein Lauf zieht sich über mehrere Anfragen: Diagnose, gegebenenfalls
 * Rückfragen, dann der Plan. Ohne diese Tabelle müsste die App das
 * Problemmodell zwischenlagern und zurückschicken — und damit wäre es
 * Nutzereingabe, die sich manipulieren ließe. Genau davor schützt §4a.
 */

interface Zeile {
  id: string;
  device_id: string;
  created_at: number;
  status: string;
  eingabe: string;
  rueckfragen: string | null;
  problemmodell: string | null;
  architektur: string | null;
  generation_id: string | null;
  bundle_id: string | null;
}

function lies<T>(roh: string | null): T | null {
  if (roh === null) return null;
  try {
    return JSON.parse(roh) as T;
  } catch {
    return null;
  }
}

function zuLauf(zeile: Zeile): Lauf {
  return {
    id: zeile.id,
    device_id: zeile.device_id,
    created_at: zeile.created_at,
    status: zeile.status as LaufStatus,
    eingabe: lies<Eingabe>(zeile.eingabe) ?? {
      vorhaben: '',
      stand: '',
      minuten_pro_tag: 0,
      tage_pro_woche: 0,
      equipment: '',
    },
    rueckfragen: lies<string[]>(zeile.rueckfragen) ?? [],
    problemmodell: lies<Problemmodell>(zeile.problemmodell),
    architektur: lies<Architektur>(zeile.architektur),
    generation_id: zeile.generation_id,
  };
}

export async function erstelleLauf(
  env: Env,
  lauf: { id: string; deviceId: string; eingabe: Eingabe; generationId: string },
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO laeufe (id, device_id, created_at, status, eingabe, generation_id)
     VALUES (?, ?, ?, 'diagnose', ?, ?)`,
  )
    .bind(lauf.id, lauf.deviceId, Date.now(), JSON.stringify(lauf.eingabe), lauf.generationId)
    .run();
}

/**
 * Lädt einen Lauf — immer zusammen mit dem Gerät.
 *
 * Die Lauf-Kennung steht in der App und ist damit ratbar; ohne die zweite
 * Bedingung könnte ein fremdes Gerät den Plan eines anderen weiterführen.
 */
export async function ladeLauf(env: Env, id: string, deviceId: string): Promise<Lauf | null> {
  const zeile = await env.DB.prepare('SELECT * FROM laeufe WHERE id = ? AND device_id = ?')
    .bind(id, deviceId)
    .first<Zeile>();
  return zeile === null ? null : zuLauf(zeile);
}

export async function merkeDiagnose(
  env: Env,
  id: string,
  problemmodell: Problemmodell,
): Promise<void> {
  const offen = problemmodell.rueckfragen.length > 0;
  await env.DB.prepare(
    'UPDATE laeufe SET status = ?, problemmodell = ?, rueckfragen = ? WHERE id = ?',
  )
    .bind(
      offen ? 'rueckfragen' : 'plan',
      JSON.stringify(problemmodell),
      JSON.stringify(problemmodell.rueckfragen),
      id,
    )
    .run();
}

export async function merkeArchitektur(
  env: Env,
  id: string,
  architektur: Architektur,
): Promise<void> {
  await env.DB.prepare('UPDATE laeufe SET architektur = ? WHERE id = ?')
    .bind(JSON.stringify(architektur), id)
    .run();
}

export async function schliesseLauf(
  env: Env,
  id: string,
  status: LaufStatus,
  bundleId: string | null,
): Promise<void> {
  await env.DB.prepare('UPDATE laeufe SET status = ?, bundle_id = ? WHERE id = ?')
    .bind(status, bundleId, id)
    .run();
}

/** Die Zahlen aus §11 als Zeitreihe, nicht als Momentaufnahme: die
 *  Wiederverwendungsquote soll steigen, und das sieht man nur im Verlauf. */
export async function schreibeKennzahlen(
  env: Env,
  laufId: string,
  k: Kennzahlen,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO lauf_kennzahlen
       (lauf_id, created_at, bedarfe, reuse, neu, neue_tags, pruefliste, uebungspositionen)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(lauf_id) DO UPDATE SET
       bedarfe = excluded.bedarfe, reuse = excluded.reuse, neu = excluded.neu,
       neue_tags = excluded.neue_tags, pruefliste = excluded.pruefliste,
       uebungspositionen = excluded.uebungspositionen`,
  )
    .bind(
      laufId,
      Date.now(),
      k.bedarfe,
      k.reuse,
      k.neu,
      k.neue_tags,
      k.pruefliste,
      k.uebungspositionen,
    )
    .run();
}

/** Welche Tags im Vokabular als Tätigkeit geführt werden. Daraus wird
 *  `Exercise.domain` — die App hat kein eigenes Bereichsfeld. */
export async function ladeTaetigkeiten(env: Env): Promise<Set<string>> {
  const ergebnis = await env.DB.prepare(
    'SELECT tag FROM tagvokabular WHERE ist_taetigkeit = 1',
  ).all<{ tag: string }>();
  return new Set(ergebnis.results.map((z) => z.tag));
}
