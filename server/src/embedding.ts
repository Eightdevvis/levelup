/**
 * Embeddings über Workers AI.
 *
 * Zwei Stellen brauchen sie: das Eindampfen der Bedarfe (§7.1) und die Suche
 * in der Bibliothek (§7.2, §9). Beide vergleichen mit derselben Schwelle, und
 * die steht deshalb hier — an genau einer Stelle, wie in der Arbeitsliste
 * festgehalten.
 */

/**
 * Ab hier gelten zwei Texte als dasselbe: beim Zusammenlegen von Bedarfen
 * (§7.1) und beim Dedupe vor dem Speichern (§9). Nicht zwei Konstanten, weil
 * ein Auseinanderdriften der beiden Werte genau den Zustand herstellt, den §7.1
 * verhindern soll — zusammengelegt beim Planen, doppelt in der Bibliothek.
 */
export const AEHNLICHKEIT_SCHWELLE = 0.9;

/** Tag-Vokabular: hier darf es enger sein, sonst wird aus "bogenführung" und
 *  "bogenhaltung" ein Tag. */
export const TAG_SCHWELLE = 0.88;

/** Workers AI nimmt pro Aufruf nur eine begrenzte Liste. Lieber in Bündeln als
 *  einzeln: ein Aufruf je Bedarf wäre bei 30 Bedarfen 30 Unteranfragen. */
const BUENDELGROESSE = 100;

/**
 * Der Text, aus dem das Embedding entsteht.
 *
 * Zweck und Tags zusammen, weil der Zweck allein zu wenig unterscheidet:
 * "Bewegung langsam ausführen und dabei zuhören" passt sonst auf Geige wie auf
 * Kniebeugen. Die Tätigkeit steht in den Tags.
 */
export function bedarfstext(zweck: string, tags: readonly string[]): string {
  return `${zweck}\n${[...tags].sort().join(', ')}`;
}

/** Derselbe Aufbau für einen fertigen Baustein — sonst vergliche man beim
 *  Retrieval Äpfel mit Birnen. */
export function bausteintext(
  titel: string,
  benefit: string,
  tags: readonly string[],
): string {
  return `${titel}. ${benefit}\n${[...tags].sort().join(', ')}`;
}

export class EmbeddingError extends Error {}

/**
 * Bettet eine Liste Texte ein. Reihenfolge bleibt erhalten.
 */
export async function bette(env: Env, texte: readonly string[]): Promise<number[][]> {
  if (texte.length === 0) return [];

  const alle: number[][] = [];
  for (let i = 0; i < texte.length; i += BUENDELGROESSE) {
    const buendel = texte.slice(i, i + BUENDELGROESSE);
    const antwort = await env.AI.run(env.MODELL_EMBEDDING, {
      text: buendel as string[],
    });

    // `bge-m3` kann vier verschiedene Antwortformen haben — Vergleich, Kontext-
    // Embeddings, einfache Embeddings und die Quittung eines asynchronen
    // Auftrags. Uns interessiert nur die dritte.
    const daten = 'data' in antwort ? antwort.data : undefined;
    if (!Array.isArray(daten) || daten.length !== buendel.length) {
      throw new EmbeddingError(
        `Erwartet wurden ${buendel.length} Vektoren, geliefert ${Array.isArray(daten) ? daten.length : 'keine'}.`,
      );
    }
    alle.push(...(daten as number[][]));
  }
  return alle;
}

/** Ein einzelner Text — für den Kurator und das Speichern eines Bausteins. */
export async function betteEinen(env: Env, text: string): Promise<number[]> {
  const [vektor] = await bette(env, [text]);
  if (vektor === undefined) throw new EmbeddingError('Kein Vektor geliefert.');
  return vektor;
}

/**
 * Kosinus-Ähnlichkeit.
 *
 * Ohne Annahme über die Länge der Vektoren: ob `bge-m3` normalisiert
 * ausliefert, steht in keiner Typdefinition, und ein Skalarprodukt auf
 * unnormalisierten Vektoren gäbe stillschweigend falsche Schwellenwerte.
 */
export function kosinus(a: readonly number[], b: readonly number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let punkt = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    punkt += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return punkt / Math.sqrt(normA * normB);
}

/**
 * Jaccard-Überschneidung zweier Tag-Mengen.
 *
 * Geht in die Reihung des Retrievals ein, damit ein Kandidat aus einer fremden
 * Tätigkeit nicht allein wegen ähnlicher Formulierung nach oben rutscht (§7.2).
 */
export function tagAnteil(a: readonly string[], b: readonly string[]): number {
  if (a.length === 0 || b.length === 0) return 0;
  const mengeA = new Set(a);
  const mengeB = new Set(b);
  let gemeinsam = 0;
  for (const tag of mengeA) if (mengeB.has(tag)) gemeinsam++;
  const vereinigung = mengeA.size + mengeB.size - gemeinsam;
  return vereinigung === 0 ? 0 : gemeinsam / vereinigung;
}
