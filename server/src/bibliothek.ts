import type { Kandidat, UebungDatensatz } from './typen';

/**
 * Lesender Zugriff auf die Bibliothek in D1.
 *
 * Die Tabelle speichert `tags` und `equipment` als JSON-Text — SQLite kennt
 * keine Listen. Das Auspacken passiert genau hier, damit der Rest des Codes nur
 * mit Objekten arbeitet.
 */

interface Zeile {
  id: string;
  titel: string;
  anleitung: string;
  benefit: string;
  tags: string;
  equipment: string;
  bild: string | null;
  animation: string | null;
  created_at: number;
  usage_count: number;
  source_program_id: string | null;
  source_device_id: string | null;
  status: string;
}

/** Kaputtes JSON in einer Spalte darf nicht den ganzen Lauf abbrechen: dann
 *  fehlt ein Kandidat, und das ist reparabel. */
function liste(roh: string): string[] {
  try {
    const wert: unknown = JSON.parse(roh);
    return Array.isArray(wert) ? wert.filter((e): e is string => typeof e === 'string') : [];
  } catch {
    return [];
  }
}

export function zeileZuUebung(zeile: Zeile): UebungDatensatz {
  return {
    id: zeile.id,
    titel: zeile.titel,
    anleitung: zeile.anleitung,
    benefit: zeile.benefit,
    tags: liste(zeile.tags),
    equipment: liste(zeile.equipment),
    bild: zeile.bild,
    animation: zeile.animation,
    created_at: zeile.created_at,
    usage_count: zeile.usage_count,
    source_program_id: zeile.source_program_id,
    source_device_id: zeile.source_device_id,
    status: zeile.status === 'zurueckgestellt' ? 'zurueckgestellt' : 'aktiv',
  };
}

function platzhalter(anzahl: number): string {
  return new Array(anzahl).fill('?').join(', ');
}

/**
 * Lädt Bausteine als Kandidaten für den Kurator: alles außer den Medien.
 *
 * `bild` und `animation` bleiben draußen, weil eine URL bei der Entscheidung
 * nicht hilft und nur Token kostet (§7.2). Ein einziger Aufruf für alle IDs —
 * einer je Kandidat wären zwanzig Unteranfragen pro Bedarf.
 */
export async function ladeKandidaten(env: Env, ids: readonly string[]): Promise<Kandidat[]> {
  if (ids.length === 0) return [];

  const ergebnis = await env.DB.prepare(
    `SELECT id, titel, anleitung, benefit, tags, equipment
       FROM uebungen
      WHERE id IN (${platzhalter(ids.length)})`,
  )
    .bind(...ids)
    .all<Pick<Zeile, 'id' | 'titel' | 'anleitung' | 'benefit' | 'tags' | 'equipment'>>();

  return ergebnis.results.map((zeile) => ({
    id: zeile.id,
    titel: zeile.titel,
    anleitung: zeile.anleitung,
    benefit: zeile.benefit,
    tags: liste(zeile.tags),
    equipment: liste(zeile.equipment),
  }));
}

/** Vollständige Datensätze, inklusive Medien — für den Zusammenbau des Bundles. */
export async function ladeUebungen(
  env: Env,
  ids: readonly string[],
): Promise<Map<string, UebungDatensatz>> {
  if (ids.length === 0) return new Map();

  const ergebnis = await env.DB.prepare(
    `SELECT * FROM uebungen WHERE id IN (${platzhalter(ids.length)})`,
  )
    .bind(...ids)
    .all<Zeile>();

  const karte = new Map<string, UebungDatensatz>();
  for (const zeile of ergebnis.results) karte.set(zeile.id, zeileZuUebung(zeile));
  return karte;
}
