import { vi } from 'vitest';
import type { Kandidat } from '../src/typen';

/**
 * Ein Doppelgänger für die Anthropic-Schnittstelle.
 *
 * Die Tests prüfen die Pipeline, nicht das Modell. Also liefert dieser hier
 * konservierte Antworten — in genau dem Ereignisformat, das `anthropic.ts`
 * liest, damit auch der Strom-Teil mitgetestet wird und nicht nur die Prüfung.
 */

export interface Aufruf {
  /** Blockform, weil der System-Prompt `cache_control` trägt. */
  system: { type: string; text: string }[];
  messages: { role: string; content: unknown }[];
  model: string;
  max_tokens: number;
}

export interface AntwortDoppel {
  /** Was das Modell schreibt. Objekte werden zu JSON, Strings gehen roh
   *  durch — für den Fall „Modell rahmt das JSON mit einem Satz ein". */
  text: string | unknown;
  stopReason?: string;
}

export interface Spion {
  aufrufe: Aufruf[];
  wiederherstellen: () => void;
}

/** Hängt sich an `globalThis.fetch` und gibt die Antworten der Reihe nach aus. */
export function fakeAnthropic(antworten: AntwortDoppel[]): Spion {
  const aufrufe: Aufruf[] = [];
  let index = 0;
  const original = globalThis.fetch;

  const gefaelscht = vi.fn(async (_url: unknown, init?: RequestInit) => {
    aufrufe.push(JSON.parse(String(init?.body)) as Aufruf);
    const dran = antworten[index++];
    if (dran === undefined) throw new Error('Mehr Aufrufe als konservierte Antworten');
    return new Response(strom(dran), { status: 200 });
  });

  globalThis.fetch = gefaelscht as unknown as typeof fetch;
  return {
    aufrufe,
    wiederherstellen: () => {
      globalThis.fetch = original;
    },
  };
}

function strom(antwort: AntwortDoppel): ReadableStream<Uint8Array> {
  const text = typeof antwort.text === 'string' ? antwort.text : JSON.stringify(antwort.text);
  const ereignisse = [
    { type: 'message_start', message: { usage: { input_tokens: 100, output_tokens: 0 } } },
    { type: 'content_block_delta', delta: { type: 'thinking_delta', thinking: 'Ich denke nach. ' } },
    { type: 'content_block_delta', delta: { type: 'text_delta', text } },
    {
      type: 'message_delta',
      delta: { stop_reason: antwort.stopReason ?? 'end_turn' },
      usage: { output_tokens: 200 },
    },
  ];

  const kodierer = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const e of ereignisse) {
        controller.enqueue(kodierer.encode(`data: ${JSON.stringify(e)}\n\n`));
      }
      controller.close();
    },
  });
}

/** Nur die Felder, die die geprüften Funktionen anfassen. */
export function testEnv(): Env {
  return {
    ANTHROPIC_API_KEY: 'test',
    MODELL_DIAGNOSE: 'claude-opus-5',
    MODELL_ARCHITEKT: 'claude-opus-5',
    MODELL_KURATOR: 'claude-opus-5',
    MODELL_EMBEDDING: '@cf/baai/bge-m3',
  } as unknown as Env;
}

// Groß genug, dass sich die Einheitsvektoren nicht in die Quere kommen: bei 32
// liefen Grundstock, Bedarfe und neue Bausteine über den Rand und zwei
// verschiedene Texte bekamen denselben Vektor — was im Test wie eine echte
// Dublette aussah.
const DIM = 256;
/** Die ersten Plätze bleiben für vorgegebene Vektoren frei, damit ein
 *  Einheitsvektor nicht zufällig neben einem davon liegt. */
const ERSTER_FREIER_PLATZ = 8;

/**
 * Ein Doppelgänger für Workers AI.
 *
 * Standardmäßig bekommt jeder verschiedene Text einen eigenen Einheitsvektor —
 * verschiedene Texte sind damit exakt unähnlich, gleiche exakt gleich. Wer
 * Ähnlichkeit *zwischen* zwei Texten testen will, gibt sie in `vorgaben` vor,
 * benannt nach der ersten Zeile des Textes (dem Zweck bzw. Titel).
 */
export function fakeAi(vorgaben: Record<string, number[]> = {}): Ai {
  const bekannt = new Map<string, number[]>();
  let naechsterPlatz = ERSTER_FREIER_PLATZ;

  const vektor = (text: string): number[] => {
    const erstezeile = text.split('\n')[0];
    const schon = bekannt.get(text);
    if (schon !== undefined) return schon;

    const vorgabe = vorgaben[erstezeile];
    const neu = new Array<number>(DIM).fill(0);
    if (vorgabe !== undefined) {
      vorgabe.forEach((wert, i) => {
        neu[i] = wert;
      });
    } else {
      neu[naechsterPlatz++ % DIM] = 1;
    }
    bekannt.set(text, neu);
    return neu;
  };

  return {
    run: async (_modell: string, eingabe: { text: string | string[] }) => {
      const texte = Array.isArray(eingabe.text) ? eingabe.text : [eingabe.text];
      return { shape: [texte.length, DIM], data: texte.map(vektor) };
    },
  } as unknown as Ai;
}

export function testEnvMitAi(vorgaben: Record<string, number[]> = {}): Env {
  return { ...testEnv(), AI: fakeAi(vorgaben) } as unknown as Env;
}

// --- Bibliothek: D1 und Vectorize -----------------------------------------

interface Bestand {
  kandidaten: Kandidat[];
  treffer: { id: string; score: number }[];
}

export interface VectorizeAufruf {
  vektor: readonly number[];
  optionen: { topK?: number; filter?: unknown };
}

/**
 * D1 und Vectorize als Doppelgänger.
 *
 * Nur so viel, wie `bibliothek.ts` und `retrieval.ts` tatsächlich aufrufen —
 * eine nachgebaute Datenbank wäre ein zweites Produkt mit eigenen Fehlern.
 */
export function fakeBibliothek(bestand: Bestand): {
  env: Env;
  vectorizeAufrufe: VectorizeAufruf[];
} {
  const vectorizeAufrufe: VectorizeAufruf[] = [];

  const DB = {
    prepare: (_sql: string) => ({
      bind: (...ids: string[]) => ({
        all: async () => ({
          results: bestand.kandidaten
            .filter((k) => ids.includes(k.id))
            .map((k) => ({
              ...k,
              tags: JSON.stringify(k.tags),
              equipment: JSON.stringify(k.equipment),
            })),
        }),
      }),
    }),
  };

  const VEC_UEBUNGEN = {
    query: async (vektor: readonly number[], optionen: { topK?: number; filter?: unknown }) => {
      vectorizeAufrufe.push({ vektor, optionen });
      return { count: bestand.treffer.length, matches: bestand.treffer };
    },
  };

  return {
    env: { ...testEnv(), DB, VEC_UEBUNGEN } as unknown as Env,
    vectorizeAufrufe,
  };
}
