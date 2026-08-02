import {
  AEHNLICHKEIT_SCHWELLE,
  bausteintext,
  bette,
  betteEinen,
  TAG_SCHWELLE,
} from './embedding';
import type { Kuratorentscheidung, NeueUebung } from './typen';

/**
 * Schritt [5]: Dedupe, Tag-Normalisierung, Speichern (Spec §9).
 *
 * Ohne diesen Schritt füllt sich die Bibliothek mit Fast-Duplikaten und die
 * Suche in 3b wird unbrauchbar. Und ohne die Tag-Normalisierung entstehen
 * `geige`, `violine` und `geigespielen` als drei getrennte Ecken derselben
 * Bibliothek — da es kein Bereichsfeld gibt, hängt hier alles dran.
 *
 * Alles läuft sequenziell innerhalb eines Laufs: ein später verarbeiteter
 * Bedarf soll die neuen Bausteine desselben Laufs schon als Kandidaten sehen.
 */

export interface Speicherergebnis {
  uebung_id: string;
  /** Was nur für diesen Nutzer gilt. Steht am Programm, nicht am Baustein. */
  kontext_hinweis: string | null;
  /** Ob ein neuer Baustein entstanden ist — Kennzahl `neu` bzw. `reuse`. */
  neu: boolean;
  /** Ob der Baustein wegen zu großer Nähe in die Prüfliste ging, statt
   *  gespeichert zu werden. Für diesen Lauf gilt dann der Bestandsbaustein. */
  zurPruefung: boolean;
  /** Tags, die es vorher im Vokabular nicht gab. */
  neueTags: string[];
  /** Der tatsächliche Ähnlichkeitswert zum nächsten Bestandsbaustein.
   *  Protokolliert, damit die geratene Schwelle 0,90 später an echten Daten
   *  justiert werden kann (§9). */
  aehnlichkeit: number | null;
}

export interface Speicherkontext {
  laufId: string;
  deviceId: string;
}

export async function verarbeiteEntscheidung(
  env: Env,
  entscheidung: Kuratorentscheidung,
  kontext: Speicherkontext,
): Promise<Speicherergebnis> {
  if (entscheidung.aktion === 'reuse') {
    // Einmal pro Lauf, nicht pro Position: sonst gewinnt eine Übung, die in
    // einem einzigen Plan zwanzigmal vorkommt, jede Rangfolge.
    await env.DB.prepare('UPDATE uebungen SET usage_count = usage_count + 1 WHERE id = ?')
      .bind(entscheidung.uebung_id)
      .run();

    return {
      uebung_id: entscheidung.uebung_id,
      kontext_hinweis: entscheidung.kontext_hinweis,
      neu: false,
      zurPruefung: false,
      neueTags: [],
      aehnlichkeit: null,
    };
  }

  return speichereNeu(env, entscheidung.neue_uebung, entscheidung.kontext_hinweis, kontext);
}

async function speichereNeu(
  env: Env,
  roh: NeueUebung,
  kontextHinweis: string | null,
  kontext: Speicherkontext,
): Promise<Speicherergebnis> {
  // Erst die Tags, dann das Embedding — der Baustein wird über seine Tags
  // mitindiziert, und normalisiert man sie danach, steht im Index ein anderer
  // Text als in der Datenbank.
  const { tags, neueTags } = await normalisiereTags(env, roh.tags);
  const uebung: NeueUebung = { ...roh, tags };

  const vektor = await betteEinen(env, bausteintext(uebung.titel, uebung.anleitung, tags));
  const treffer = await env.VEC_UEBUNGEN.query(vektor, { topK: 1, filter: { status: 'aktiv' } });
  const naechster = treffer.matches[0];
  const aehnlichkeit = naechster?.score ?? null;

  protokolliere({
    ereignis: 'dedupe',
    lauf_id: kontext.laufId,
    titel: uebung.titel,
    aehnlichkeit,
    schwelle: AEHNLICHKEIT_SCHWELLE,
    bestand_id: naechster?.id ?? null,
  });

  if (naechster !== undefined && naechster.score >= AEHNLICHKEIT_SCHWELLE) {
    // Nicht automatisch verwerfen: bei Übungen liegen echte Varianten und echte
    // Dubletten dicht beieinander, und eine Maschine, die hier selbst
    // entscheidet, verliert Varianten (§9).
    await env.DB.prepare(
      `INSERT INTO pruefliste (id, created_at, lauf_id, kandidat, bestand_id, aehnlichkeit, status)
       VALUES (?, ?, ?, ?, ?, ?, 'offen')`,
    )
      .bind(
        crypto.randomUUID(),
        Date.now(),
        kontext.laufId,
        JSON.stringify(uebung),
        naechster.id,
        naechster.score,
      )
      .run();

    await env.DB.prepare('UPDATE uebungen SET usage_count = usage_count + 1 WHERE id = ?')
      .bind(naechster.id)
      .run();

    return {
      uebung_id: naechster.id,
      kontext_hinweis: kontextHinweis,
      neu: false,
      zurPruefung: true,
      neueTags,
      aehnlichkeit,
    };
  }

  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO uebungen
       (id, titel, anleitung, benefit, tags, equipment, bild, animation,
        created_at, usage_count, source_program_id, source_device_id, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 'aktiv')`,
  )
    .bind(
      id,
      uebung.titel,
      uebung.anleitung,
      uebung.benefit,
      JSON.stringify(tags),
      JSON.stringify(uebung.equipment),
      uebung.bild,
      uebung.animation,
      Date.now(),
      kontext.laufId,
      kontext.deviceId,
    )
    .run();

  // Erst nach dem Schreiben in D1: ein Vektor ohne Zeile wäre ein Treffer, zu
  // dem sich nichts nachladen lässt.
  await env.VEC_UEBUNGEN.upsert([{ id, values: vektor, metadata: { status: 'aktiv' } }]);

  return {
    uebung_id: id,
    kontext_hinweis: kontextHinweis,
    neu: true,
    zurPruefung: false,
    neueTags,
    aehnlichkeit,
  };
}

// --- Tag-Vokabular ---------------------------------------------------------

export interface Tagergebnis {
  /** Die Tags, wie sie gespeichert werden — bekannte statt naher Varianten. */
  tags: string[];
  /** Die davon, die neu ins Vokabular aufgenommen wurden. */
  neueTags: string[];
}

/**
 * Gleicht neue Tags gegen das gewachsene Vokabular ab (§9).
 *
 * Zwei Stufen: erst ein einziger Blick in D1, ob es die Schreibweise schon
 * gibt — das trifft den Normalfall und kostet eine Abfrage für alle Tags
 * zusammen. Nur was übrig bleibt, geht in die Vektorsuche.
 */
export async function normalisiereTags(
  env: Env,
  roh: readonly string[],
): Promise<Tagergebnis> {
  if (roh.length === 0) return { tags: [], neueTags: [] };

  const eindeutig = [...new Set(roh)];
  const platzhalter = new Array(eindeutig.length).fill('?').join(', ');
  const bekannt = await env.DB.prepare(
    `SELECT tag FROM tagvokabular WHERE tag IN (${platzhalter})`,
  )
    .bind(...eindeutig)
    .all<{ tag: string }>();

  const wortgleich = new Set(bekannt.results.map((z) => z.tag));
  const offen = eindeutig.filter((t) => !wortgleich.has(t));

  const endgueltig = new Set(eindeutig.filter((t) => wortgleich.has(t)));
  const neueTags: string[] = [];

  if (offen.length > 0) {
    const vektoren = await bette(env, offen);
    for (let i = 0; i < offen.length; i++) {
      const tag = offen[i];
      const treffer = await env.VEC_TAGS.query(vektoren[i], { topK: 1 });
      const naechster = treffer.matches[0];

      protokolliere({
        ereignis: 'tag',
        tag,
        aehnlichkeit: naechster?.score ?? null,
        schwelle: TAG_SCHWELLE,
        bestand: naechster?.id ?? null,
      });

      if (naechster !== undefined && naechster.score >= TAG_SCHWELLE) {
        // "violine" wird zu "geige", wenn "geige" schon im Vokabular steht.
        endgueltig.add(naechster.id);
        continue;
      }

      endgueltig.add(tag);
      neueTags.push(tag);
      await env.DB.prepare(
        `INSERT INTO tagvokabular (tag, count, ist_taetigkeit, created_at)
         VALUES (?, 0, 0, ?)
         ON CONFLICT(tag) DO NOTHING`,
      )
        .bind(tag, Date.now())
        .run();
      await env.VEC_TAGS.upsert([{ id: tag, values: vektoren[i] }]);
    }
  }

  const tags = [...endgueltig];
  await zaehleTags(env, tags);
  return { tags, neueTags };
}

/** `count` sagt, wie eingebürgert ein Tag ist — bei zwei ähnlichen gewinnt der
 *  häufigere. Eine Anweisung für alle Tags, nicht eine je Tag. */
async function zaehleTags(env: Env, tags: readonly string[]): Promise<void> {
  if (tags.length === 0) return;
  const platzhalter = new Array(tags.length).fill('?').join(', ');
  await env.DB.prepare(
    `UPDATE tagvokabular SET count = count + 1 WHERE tag IN (${platzhalter})`,
  )
    .bind(...tags)
    .run();
}

/**
 * Strukturiert protokollieren, damit sich die geratenen Schwellen nach den
 * ersten paar hundert Bausteinen an echten Daten justieren lassen (§9). Ohne
 * das bleibt 0,90 für immer eine Zahl, die jemand einmal hingeschrieben hat.
 */
function protokolliere(zeile: Record<string, unknown>): void {
  console.log(JSON.stringify(zeile));
}
