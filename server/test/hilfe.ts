import { vi } from 'vitest';

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
