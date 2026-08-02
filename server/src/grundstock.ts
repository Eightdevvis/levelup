import { bausteintext, bette } from './embedding';
import { pruefeBaustein } from './pruefen';
import type { NeueUebung } from './typen';

/**
 * Der Kaltstart (Spec §10).
 *
 * Bewusst am Dedupe vorbei: die Bausteine sind von Hand geschrieben, und gegen
 * eine leere Bibliothek zu entdoppeln hieße, den Maßstab an sich selbst zu
 * messen. Stattdessen feste Kennungen — wer das Skript zweimal laufen lässt,
 * bekommt keine zweite Bibliothek.
 *
 * Auch die Tags gehen ungefiltert ins Vokabular: sie *sind* der Maßstab, an
 * dem später alles andere normalisiert wird.
 */

export interface Grundstockdatei {
  taetigkeit: string;
  bausteine: (NeueUebung & { id: string })[];
}

export interface Einspielbericht {
  taetigkeit: string;
  angelegt: string[];
  uebersprungen: string[];
  fehler: string[];
}

export function pruefeGrundstock(roh: unknown): Grundstockdatei | string[] {
  if (typeof roh !== 'object' || roh === null) return ['Kein Objekt.'];
  const o = roh as Record<string, unknown>;
  if (typeof o.taetigkeit !== 'string' || o.taetigkeit.trim().length === 0) {
    return ['taetigkeit: fehlt'];
  }
  if (!Array.isArray(o.bausteine)) return ['bausteine: fehlt oder ist keine Liste'];

  const fehler: string[] = [];
  const bausteine: (NeueUebung & { id: string })[] = [];

  o.bausteine.forEach((roher, i) => {
    const id = (roher as Record<string, unknown>)?.id;
    if (typeof id !== 'string' || id.trim().length === 0) {
      fehler.push(`bausteine[${i}].id: fehlt`);
      return;
    }
    const geprueft = pruefeBaustein(roher);
    if (!geprueft.ok) {
      fehler.push(...geprueft.fehler.map((f) => `bausteine[${i}] · ${f}`));
      return;
    }
    bausteine.push({ ...geprueft.wert, id });
  });

  return fehler.length > 0 ? fehler : { taetigkeit: o.taetigkeit.trim(), bausteine };
}

export async function spieleEin(env: Env, datei: Grundstockdatei): Promise<Einspielbericht> {
  const bericht: Einspielbericht = {
    taetigkeit: datei.taetigkeit,
    angelegt: [],
    uebersprungen: [],
    fehler: [],
  };
  if (datei.bausteine.length === 0) return bericht;

  const platzhalter = datei.bausteine.map(() => '?').join(', ');
  const vorhanden = await env.DB.prepare(
    `SELECT id FROM uebungen WHERE id IN (${platzhalter})`,
  )
    .bind(...datei.bausteine.map((b) => b.id))
    .all<{ id: string }>();
  const schonDa = new Set(vorhanden.results.map((z) => z.id));

  const offen = datei.bausteine.filter((b) => !schonDa.has(b.id));
  bericht.uebersprungen = [...schonDa];
  if (offen.length === 0) return bericht;

  // Ein Aufruf für alle Bausteine und ein zweiter für alle Tags — `bge-m3`
  // nimmt eine Liste, und zwei Dutzend Einzelaufrufe wären zwei Dutzend
  // Unteranfragen.
  const vektoren = await bette(
    env,
    offen.map((b) => bausteintext(b.titel, b.anleitung, b.tags)),
  );

  const alleTags = [...new Set(offen.flatMap((b) => b.tags))];
  const tagVektoren = await bette(env, alleTags);

  const jetzt = Date.now();
  for (let i = 0; i < alleTags.length; i++) {
    const tag = alleTags[i];
    await env.DB.prepare(
      `INSERT INTO tagvokabular (tag, count, ist_taetigkeit, created_at)
       VALUES (?, 0, ?, ?)
       ON CONFLICT(tag) DO UPDATE SET ist_taetigkeit = MAX(ist_taetigkeit, excluded.ist_taetigkeit)`,
    )
      .bind(tag, tag === datei.taetigkeit ? 1 : 0, jetzt)
      .run();
    await env.VEC_TAGS.upsert([{ id: tag, values: tagVektoren[i] }]);
  }

  for (let i = 0; i < offen.length; i++) {
    const baustein = offen[i];
    await env.DB.prepare(
      `INSERT INTO uebungen
         (id, titel, anleitung, benefit, tags, equipment, bild, animation,
          created_at, usage_count, source_program_id, source_device_id, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 'aktiv')`,
    )
      .bind(
        baustein.id,
        baustein.titel,
        baustein.anleitung,
        baustein.benefit,
        JSON.stringify(baustein.tags),
        JSON.stringify(baustein.equipment),
        baustein.bild,
        baustein.animation,
        jetzt,
        null,
        null,
      )
      .run();
    await env.VEC_UEBUNGEN.upsert([
      { id: baustein.id, values: vektoren[i], metadata: { status: 'aktiv' } },
    ]);
    bericht.angelegt.push(baustein.id);
  }

  await env.DB.prepare(
    `UPDATE tagvokabular SET count = count + 1 WHERE tag IN (${alleTags.map(() => '?').join(', ')})`,
  )
    .bind(...alleTags)
    .run();

  return bericht;
}
