import { bausteintext, kosinus } from '../src/embedding';
import type { NeueUebung } from '../src/typen';
import { fakeAi, testEnv } from './hilfe';

/**
 * D1 und Vectorize im Speicher.
 *
 * Größer als ein Doppelgänger sonst sein sollte — aber Dedupe,
 * Tag-Normalisierung und die Reihenfolge innerhalb eines Laufs sind genau das
 * Zusammenspiel dieser drei Dienste. Einzeln geprüft bliebe die Frage offen,
 * ob der zweite Bedarf den Baustein des ersten sieht.
 *
 * Die Anweisungen werden am Text erkannt. Das ist grob, hält aber genau die
 * Abfragen fest, die der Code wirklich stellt: kommt eine neue dazu, fällt sie
 * hier auf, statt still ins Leere zu laufen.
 */

export interface UebungZeile {
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

export interface Pruefzeile {
  id: string;
  lauf_id: string;
  kandidat: string;
  bestand_id: string;
  aehnlichkeit: number;
}

export interface Speicher {
  env: Env;
  uebungen: Map<string, UebungZeile>;
  tagvokabular: Map<string, { count: number }>;
  pruefliste: Pruefzeile[];
  vektoren: Map<string, { werte: number[]; status: string }>;
  tagVektoren: Map<string, number[]>;
  /** Legt einen Baustein an, als wäre er schon in der Bibliothek. */
  lege: (uebung: NeueUebung & { id: string }) => Promise<void>;
}

interface VecTreffer {
  id: string;
  score: number;
}

function suche(
  vektoren: Iterable<[string, number[]]>,
  frage: readonly number[],
  topK: number,
): VecTreffer[] {
  return [...vektoren]
    .map(([id, werte]) => ({ id, score: kosinus(frage, werte) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, topK);
}

export function fakeSpeicher(vorgaben: Record<string, number[]> = {}): Speicher {
  const uebungen = new Map<string, UebungZeile>();
  const tagvokabular = new Map<string, { count: number }>();
  const pruefliste: Pruefzeile[] = [];
  const vektoren = new Map<string, { werte: number[]; status: string }>();
  const tagVektoren = new Map<string, number[]>();
  const ai = fakeAi(vorgaben);

  const anweisung = (sql: string, args: unknown[]) => ({
    all: async () => ({ results: lies(sql, args) }),
    run: async () => {
      schreibe(sql, args);
      return { success: true };
    },
    first: async () => lies(sql, args)[0] ?? null,
  });

  const lies = (sql: string, args: unknown[]): Record<string, unknown>[] => {
    if (sql.includes('FROM tagvokabular')) {
      return args
        .filter((a): a is string => typeof a === 'string' && tagvokabular.has(a))
        .map((tag) => ({ tag }));
    }
    if (sql.includes('FROM uebungen')) {
      const ids = args.filter((a): a is string => typeof a === 'string');
      return [...uebungen.values()]
        .filter((z) => ids.includes(z.id))
        .map((z) => ({ ...z }) as Record<string, unknown>);
    }
    throw new Error(`Unbekannte Leseanweisung: ${sql}`);
  };

  const schreibe = (sql: string, args: unknown[]): void => {
    if (sql.includes('UPDATE uebungen SET usage_count')) {
      const zeile = uebungen.get(String(args[0]));
      if (zeile !== undefined) zeile.usage_count += 1;
      return;
    }
    if (sql.includes('INSERT INTO uebungen')) {
      const [id, titel, anleitung, benefit, tags, equipment, bild, animation, created_at, prog, dev] =
        args;
      uebungen.set(String(id), {
        id: String(id),
        titel: String(titel),
        anleitung: String(anleitung),
        benefit: String(benefit),
        tags: String(tags),
        equipment: String(equipment),
        bild: bild === null ? null : String(bild),
        animation: animation === null ? null : String(animation),
        created_at: Number(created_at),
        usage_count: 1,
        source_program_id: prog === null ? null : String(prog),
        source_device_id: dev === null ? null : String(dev),
        status: 'aktiv',
      });
      return;
    }
    if (sql.includes('INSERT INTO pruefliste')) {
      const [id, , lauf_id, kandidat, bestand_id, aehnlichkeit] = args;
      pruefliste.push({
        id: String(id),
        lauf_id: String(lauf_id),
        kandidat: String(kandidat),
        bestand_id: String(bestand_id),
        aehnlichkeit: Number(aehnlichkeit),
      });
      return;
    }
    if (sql.includes('INSERT INTO tagvokabular')) {
      const tag = String(args[0]);
      if (!tagvokabular.has(tag)) tagvokabular.set(tag, { count: 0 });
      return;
    }
    if (sql.includes('UPDATE tagvokabular SET count')) {
      for (const arg of args) {
        const eintrag = tagvokabular.get(String(arg));
        if (eintrag !== undefined) eintrag.count += 1;
      }
      return;
    }
    throw new Error(`Unbekannte Schreibanweisung: ${sql}`);
  };

  const env = {
    ...testEnv(),
    AI: ai,
    DB: {
      prepare: (sql: string) => ({
        bind: (...args: unknown[]) => anweisung(sql, args),
        ...anweisung(sql, []),
      }),
    },
    VEC_UEBUNGEN: {
      query: async (
        frage: number[],
        optionen: { topK?: number; filter?: { status?: string } },
      ) => {
        const erlaubt = [...vektoren.entries()]
          .filter(([, v]) => optionen.filter?.status === undefined || v.status === optionen.filter.status)
          .map(([id, v]) => [id, v.werte] as [string, number[]]);
        const matches = suche(erlaubt, frage, optionen.topK ?? 5);
        return { count: matches.length, matches };
      },
      upsert: async (eintraege: { id: string; values: number[]; metadata?: { status?: string } }[]) => {
        for (const e of eintraege) {
          vektoren.set(e.id, { werte: e.values, status: e.metadata?.status ?? 'aktiv' });
        }
        return { mutationId: 'test' };
      },
    },
    VEC_TAGS: {
      query: async (frage: number[], optionen: { topK?: number }) => {
        const matches = suche(tagVektoren.entries(), frage, optionen.topK ?? 5);
        return { count: matches.length, matches };
      },
      upsert: async (eintraege: { id: string; values: number[] }[]) => {
        for (const e of eintraege) tagVektoren.set(e.id, e.values);
        return { mutationId: 'test' };
      },
    },
  } as unknown as Env;

  const lege = async (uebung: NeueUebung & { id: string }): Promise<void> => {
    uebungen.set(uebung.id, {
      id: uebung.id,
      titel: uebung.titel,
      anleitung: uebung.anleitung,
      benefit: uebung.benefit,
      tags: JSON.stringify(uebung.tags),
      equipment: JSON.stringify(uebung.equipment),
      bild: uebung.bild,
      animation: uebung.animation,
      created_at: 0,
      usage_count: 0,
      source_program_id: null,
      source_device_id: null,
      status: 'aktiv',
    });

    const text = bausteintext(uebung.titel, uebung.anleitung, uebung.tags);
    const antwort = (await ai.run(env.MODELL_EMBEDDING, { text })) as { data: number[][] };
    vektoren.set(uebung.id, { werte: antwort.data[0], status: 'aktiv' });

    for (const tag of uebung.tags) {
      if (!tagvokabular.has(tag)) tagvokabular.set(tag, { count: 1 });
      const tagAntwort = (await ai.run(env.MODELL_EMBEDDING, { text: tag })) as { data: number[][] };
      tagVektoren.set(tag, tagAntwort.data[0]);
    }
  };

  return { env, uebungen, tagvokabular, pruefliste, vektoren, tagVektoren, lege };
}
