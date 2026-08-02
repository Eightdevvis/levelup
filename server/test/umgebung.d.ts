/**
 * Der Testlauf ist Node, der Worker ist es nicht.
 *
 * Statt `@types/node` in ein Workers-Projekt zu ziehen — wo es `fetch`,
 * `Response` und Konsorten überschatten würde — steht hier genau das bisschen,
 * was die Tests wirklich benutzen.
 */

declare module 'node:fs' {
  export function readFileSync(pfad: string | URL, kodierung: 'utf8'): string;
}

interface ImportMeta {
  readonly url: string;
}
