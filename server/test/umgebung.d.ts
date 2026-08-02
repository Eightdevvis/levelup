/**
 * Der Testlauf ist Node, der Worker ist es nicht.
 *
 * Statt `@types/node` in ein Workers-Projekt zu ziehen — wo es `fetch`,
 * `Response` und Konsorten überschatten würde — steht hier genau das bisschen,
 * was die Tests wirklich benutzen.
 */

declare module 'node:fs' {
  export function readFileSync(pfad: string | URL, kodierung: 'utf8'): string;
  export function writeFileSync(pfad: string, inhalt: string): void;
  export function mkdirSync(pfad: string, optionen?: { recursive?: boolean }): void;
}

/** Nur die Umgebungsvariablen, die der Vergleichslauf liest. Der Schlüssel
 *  kommt von außen und wird nirgends hingeschrieben. */
declare const process: {
  env: Record<string, string | undefined>;
};

interface ImportMeta {
  readonly url: string;
}
