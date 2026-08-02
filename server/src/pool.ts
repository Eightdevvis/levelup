

/** Höchstens so viele Stichwörter, damit die Abfrage nicht ausufert. */
const MAX_TERMS = 8;



/**
 * Der Katalog für die offene Bibliothek in der App.
 *
 * Zählwerte kommen über JSON1 direkt aus dem gespeicherten Bundle, statt sie
 * als eigene Spalten zu führen — sonst müssten sie beim Schreiben gepflegt und
 * bei jeder Schemaänderung nachgezogen werden.
 */
/** Das Feld, gegen das gesucht wird. */
function searchable(...parts: (string | null | undefined)[]): string {
  return parts
    .filter((p): p is string => typeof p === 'string' && p.length > 0)
    .join(' ')
    .toLowerCase();
}

/** Tags als kommagetrennte Zeichenkette, wie die Spalte sie hält. */
function tagsOf(raw: unknown): string {
  return Array.isArray(raw)
    ? raw.filter((t) => typeof t === 'string').join(',')
    : '';
}

export async function listPrograms(
  env: Env,
  limit = 100,
): Promise<Record<string, unknown>[]> {
  const result = await env.DB.prepare(
    `SELECT id, name, domain, description, weeks, used_count,
            COALESCE(json_array_length(json, '$.exercises'), 0) AS exercises,
            COALESCE(json_array_length(json, '$.programs[0].phases'), 0)
              AS phases
       FROM pool_programs
      ORDER BY used_count DESC, created_at DESC
      LIMIT ?`,
  )
    .bind(limit)
    .all<Record<string, unknown>>();

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



interface RawProgram {
  id?: unknown;
  name?: unknown;
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

  const tags = tagsOf(raw.tags);
  // Die Tätigkeit steht als erster Tag — ein eigenes `domain` gibt es am
  // Programm nicht mehr. Die Spalte bleibt, weil die offene Bibliothek danach
  // gruppiert und sortiert; gefüllt wird sie aus den Tags.
  const domain = tags.split(',')[0].trim() || null;
  const description =
    typeof raw.description === 'string' ? raw.description : null;
  const rationale = typeof raw.rationale === 'string' ? raw.rationale : null;
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
