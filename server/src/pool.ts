/**
 * Der geteilte Pool aus Übungen und angenommenen Plänen.
 *
 * Zweck: nicht für jeden Nutzer dieselbe Übung neu erfinden lassen. Wer
 * Blattlesen übt, braucht kein neues "Rhythmus klopfen" — das gibt es schon,
 * ist erprobt, und wenn es übernommen wird, kennt die App es bereits.
 *
 * Gesucht wird bewusst schlicht: Stichwörter gegen ein vorbereitetes Suchfeld,
 * gezählt und sortiert. Kein FTS5, keine Vektoren. Der semantische Teil sitzt
 * nicht in der Datenbank, sondern im Modell: es formuliert die Stichwörter und
 * es beurteilt die Treffer. Eine Volltextsuche mit deutschem Stemming wäre
 * hier nur scheingenau. Wenn der Pool fünfstellig wird, ist das die Stelle zum
 * Austauschen — die Schnittstelle bleibt dieselbe.
 */

export interface ExerciseHit {
  id: string;
  name: string;
  domain: string | null;
  summary: string | null;
  tags: string | null;
}

export interface ProgramHit {
  id: string;
  name: string;
  domain: string | null;
  description: string | null;
  rationale: string | null;
  weeks: number;
}

/** Höchstens so viele Stichwörter, damit die Abfrage nicht ausufert. */
const MAX_TERMS = 8;

/**
 * Macht aus den Stichwörtern des Modells brauchbare Suchmuster.
 *
 * Ein einzelner Buchstabe träfe alles und wäre wertlos, deshalb fliegt alles
 * unter zwei Zeichen raus. `%` und `_` haben in LIKE eine Bedeutung und werden
 * entschärft, sonst könnte ein Stichwort die Suche aufspannen.
 */
function patterns(terms: unknown): string[] {
  if (!Array.isArray(terms)) return [];
  const out: string[] = [];
  for (const term of terms) {
    if (typeof term !== 'string') continue;
    const clean = term.trim().toLowerCase().replace(/[%_\\]/g, '');
    if (clean.length < 2) continue;
    out.push(`%${clean}%`);
    if (out.length === MAX_TERMS) break;
  }
  return out;
}

/** Das Feld, gegen das gesucht wird. */
function searchable(...parts: (string | null | undefined)[]): string {
  return parts
    .filter((p): p is string => typeof p === 'string' && p.length > 0)
    .join(' ')
    .toLowerCase();
}

function tagsOf(raw: unknown): string {
  return Array.isArray(raw)
    ? raw.filter((t) => typeof t === 'string').join(',')
    : '';
}

/**
 * Baut die Punktezählung: ein Treffer je passendem Stichwort.
 *
 * Der Umweg über die Unterabfrage ist nötig, weil SQLite einen Spaltennamen
 * aus dem SELECT nicht im WHERE kennt.
 */
function scoredQuery(table: string, columns: string, count: number): string {
  const score = Array.from(
    { length: count },
    (_, i) => `(CASE WHEN search LIKE ?${i + 1} THEN 1 ELSE 0 END)`,
  ).join(' + ');

  return `SELECT ${columns} FROM (
            SELECT ${columns}, used_count, (${score}) AS score
            FROM ${table}
          )
          WHERE score > 0
          ORDER BY score DESC, used_count DESC
          LIMIT ?${count + 1}`;
}

export async function searchExercises(
  env: Env,
  terms: unknown,
  limit = 12,
): Promise<ExerciseHit[]> {
  const args = patterns(terms);
  if (args.length === 0) return [];

  const result = await env.DB.prepare(
    scoredQuery('pool_exercises', 'id, name, domain, summary, tags', args.length),
  )
    .bind(...args, limit)
    .all<ExerciseHit>();

  return result.results ?? [];
}

export async function searchPrograms(
  env: Env,
  terms: unknown,
  limit = 6,
): Promise<ProgramHit[]> {
  const args = patterns(terms);
  if (args.length === 0) return [];

  const result = await env.DB.prepare(
    scoredQuery(
      'pool_programs',
      'id, name, domain, description, rationale, weeks',
      args.length,
    ),
  )
    .bind(...args, limit)
    .all<ProgramHit>();

  return result.results ?? [];
}

/** Das vollständige Bundle eines Plans, zum Übernehmen und Anpassen. */
export async function loadProgram(
  env: Env,
  id: unknown,
): Promise<unknown | null> {
  if (typeof id !== 'string' || id.length === 0) return null;
  const row = await env.DB.prepare(
    'SELECT json FROM pool_programs WHERE id = ?',
  )
    .bind(id)
    .first<{ json: string }>();
  if (row === null) return null;

  try {
    return JSON.parse(row.json);
  } catch {
    return null;
  }
}

interface RawExercise {
  id?: unknown;
  name?: unknown;
  domain?: unknown;
  summary?: unknown;
  tags?: unknown;
}

/**
 * Legt Übungen in den Pool.
 *
 * Bei gleicher Kennung gewinnt die zuerst eingetragene Fassung und der Zähler
 * steigt. Das ist Absicht: eine Übung, die schon oft genutzt wurde, soll nicht
 * von einer späteren Variante überschrieben werden. Die Kennungen tragen laut
 * Prompt ihre Domäne vorne ("geige-rhythmus-klopfen"), damit sich ein
 * Geigen-Aufwärmen und ein Tipp-Aufwärmen nicht in die Quere kommen.
 */
export async function storeExercises(
  env: Env,
  exercises: unknown,
  deviceId: string,
): Promise<number> {
  if (!Array.isArray(exercises) || exercises.length === 0) return 0;
  const now = Date.now();

  const statements: D1PreparedStatement[] = [];
  for (const raw of exercises) {
    if (typeof raw !== 'object' || raw === null) continue;
    const ex = raw as RawExercise;
    if (typeof ex.id !== 'string' || typeof ex.name !== 'string') continue;

    const domain = typeof ex.domain === 'string' ? ex.domain : null;
    const summary = typeof ex.summary === 'string' ? ex.summary : null;
    const tags = tagsOf(ex.tags);

    statements.push(
      env.DB.prepare(
        `INSERT INTO pool_exercises
           (id, name, domain, summary, tags, json, created_at, device_id,
            used_count, search)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
         ON CONFLICT(id) DO UPDATE SET used_count = used_count + 1`,
      ).bind(
        ex.id,
        ex.name,
        domain,
        summary,
        tags,
        JSON.stringify(raw),
        now,
        deviceId,
        searchable(ex.name, summary, tags, domain),
      ),
    );
  }

  if (statements.length === 0) return 0;
  await env.DB.batch(statements);
  return statements.length;
}

interface RawProgram {
  id?: unknown;
  name?: unknown;
  domain?: unknown;
  description?: unknown;
  rationale?: unknown;
  tags?: unknown;
  phases?: unknown;
}

/**
 * Legt einen angenommenen Plan in den Pool.
 *
 * Gespeichert wird das ganze Bundle, damit ein späterer Plan es übernehmen und
 * anpassen kann, statt nur eine Beschreibung zu sehen. Der persönliche Teil
 * gehört nicht dazu — der wird eine Ebene höher entfernt, bevor diese Funktion
 * das Bundle überhaupt sieht.
 */
export async function storeProgram(
  env: Env,
  bundle: Record<string, unknown>,
  deviceId: string,
): Promise<boolean> {
  const programs = bundle.programs;
  if (!Array.isArray(programs) || programs.length === 0) return false;

  const raw = programs[0] as RawProgram;
  if (typeof raw.id !== 'string' || typeof raw.name !== 'string') return false;

  const domain = typeof raw.domain === 'string' ? raw.domain : null;
  const description =
    typeof raw.description === 'string' ? raw.description : null;
  const rationale = typeof raw.rationale === 'string' ? raw.rationale : null;
  const tags = tagsOf(raw.tags);
  const weeks = Array.isArray(raw.phases)
    ? raw.phases.reduce<number>((sum, phase) => {
        const w = (phase as { weeks?: unknown }).weeks;
        return sum + (typeof w === 'number' ? w : 0);
      }, 0)
    : 0;

  await env.DB.prepare(
    `INSERT INTO pool_programs
       (id, name, domain, description, rationale, tags, weeks, json,
        created_at, device_id, used_count, search)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
     ON CONFLICT(id) DO UPDATE SET used_count = used_count + 1`,
  )
    .bind(
      raw.id,
      raw.name,
      domain,
      description,
      rationale,
      tags,
      weeks,
      JSON.stringify(bundle),
      Date.now(),
      deviceId,
      searchable(raw.name, description, rationale, tags, domain),
    )
    .run();

  return true;
}
