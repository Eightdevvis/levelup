import { ladeKandidaten } from './bibliothek';
import { tagAnteil } from './embedding';
import type { Melder } from './ereignisse';
import type { Bedarf, Kandidat } from './typen';

/**
 * Schritt [3b]: die Suche in der Bibliothek (Spec §7.2).
 *
 * Sie macht der Code, nicht die KI. Die KI kennt den Bestand nicht und würde
 * entweder Titel halluzinieren oder aus Bequemlichkeit neu erzeugen. Erst die
 * hier gefundenen Kandidaten gehen an den Kurator, der dann nur noch auswählt
 * oder ergänzt.
 */

/**
 * Wie stark gemeinsame Tags die Reihung verschieben.
 *
 * Startwert aus der Arbeitsliste. Als Konstante, weil er an echten Daten
 * justiert werden muss: zu klein, und ein Kandidat aus fremder Tätigkeit
 * rutscht wegen ähnlicher Formulierung nach oben; zu groß, und die Suche findet
 * nichts mehr außerhalb der schon vergebenen Tags.
 */
export const TAG_GEWICHT = 0.5;

/** Vectorize liefert breit, entschieden wird nach dem Umsortieren. */
const TOP_K = 20;

/** Was der Kurator zu sehen bekommt. Weniger als fünf lohnt die Auswahl nicht,
 *  mehr als zehn ist Kontext, den er ohnehin überfliegt (§7.2). */
export const MAX_KANDIDATEN = 10;

export interface Treffer {
  id: string;
  score: number;
}

/**
 * Sortiert die Treffer neu: `score * (1 + gewicht * tagAnteil)`.
 *
 * Ohne diesen Schritt gewinnt „langsam ausführen und dabei genau hinhören" für
 * einen Geigen-Bedarf auch dann, wenn der Baustein aus dem Krafttraining kommt
 * — die Formulierung ist dieselbe, die Tätigkeit nicht.
 */
export function reihe(
  treffer: readonly Treffer[],
  kandidaten: readonly Kandidat[],
  bedarfsTags: readonly string[],
): Kandidat[] {
  const nachId = new Map(kandidaten.map((k) => [k.id, k]));

  return treffer
    .map((t) => {
      const kandidat = nachId.get(t.id);
      if (kandidat === undefined) return null;
      const anteil = tagAnteil(bedarfsTags, kandidat.tags);
      return { kandidat, gewichtet: t.score * (1 + TAG_GEWICHT * anteil) };
    })
    .filter((e): e is { kandidat: Kandidat; gewichtet: number } => e !== null)
    .sort((a, b) => b.gewichtet - a.gewichtet)
    .slice(0, MAX_KANDIDATEN)
    .map((e) => e.kandidat);
}

/**
 * Sucht die Kandidaten zu einem Bedarf.
 *
 * `vektor` kommt aus dem Eindampfen (§7.1) — derselbe Text, dasselbe Embedding,
 * kein zweiter Aufruf.
 */
export async function sucheKandidaten(
  env: Env,
  bedarf: Bedarf,
  vektor: readonly number[],
  melde?: Melder,
): Promise<Kandidat[]> {
  const antwort = await env.VEC_UEBUNGEN.query(vektor as number[], {
    topK: TOP_K,
    // Zurückgestellte Bausteine fallen aus der Suche, ohne dass Verweise aus
    // alten Plänen ins Leere zeigen.
    filter: { status: 'aktiv' },
  });

  const treffer: Treffer[] = antwort.matches.map((m) => ({ id: m.id, score: m.score }));

  // Die Zeilen werden vor dem Umsortieren geladen, nicht danach: die Tags für
  // die Gewichtung stehen in D1, nicht im Vektorindex. Es bleibt eine einzige
  // Abfrage — nur mit zwanzig IDs statt mit zehn.
  const kandidaten = await ladeKandidaten(
    env,
    treffer.map((t) => t.id),
  );
  const gereiht = reihe(treffer, kandidaten, bedarf.tags);

  melde?.({ type: 'search', tool: 'bibliothek', terms: bedarf.tags, hits: gereiht.length });
  return gereiht;
}
