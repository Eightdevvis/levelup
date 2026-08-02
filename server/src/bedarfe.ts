import { AEHNLICHKEIT_SCHWELLE, bedarfstext, bette, kosinus } from './embedding';
import type { Architektur, Bedarf, Position } from './typen';

/**
 * Schritt [3]: aus Übungspositionen werden Bedarfe (Spec §7.1).
 *
 * Ein Plan mit 3 Phasen × 6 Einheiten × 4 Übungen hat 72 Positionen, aber weit
 * weniger verschiedene Bedarfe — Wiederholung ist ja gewollt. Der Kurator läuft
 * einmal je Bedarf.
 *
 * Das spart nicht nur Aufrufe: ohne diesen Schritt kann derselbe Bedarf in
 * Einheit 3 wiederverwendet und in Einheit 9 neu erzeugt werden, und der Nutzer
 * sähe zweimal dasselbe unter zwei Namen.
 */

/** Kleinschreibung, Satzzeichen weg, Mehrfach-Leerzeichen weg. Damit fällt
 *  „Ton gegen Bordun abgleichen." mit „ton gegen bordun abgleichen" zusammen. */
export function normalisiereZweck(roh: string): string {
  return roh
    .toLowerCase()
    .replace(/[.,;:!?„“"'()\[\]–—-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function schluessel(zweck: string, tags: readonly string[]): string {
  return `${normalisiereZweck(zweck)}|${[...tags].sort().join(',')}`;
}

interface Planposition extends Position {
  zweck: string;
  tags: string[];
}

/** Alle Übungspositionen des Plans, mit ihrer Herkunft. */
export function sammlePositionen(architektur: Architektur): Planposition[] {
  const positionen: Planposition[] = [];
  architektur.phasen.forEach((phase, p) => {
    phase.einheiten.forEach((einheit, e) => {
      einheit.uebungen.forEach((uebung, i) => {
        positionen.push({
          phase: p,
          einheit: e,
          index: i,
          dauer_min: uebung.dauer_min,
          zweck: uebung.zweck,
          tags: uebung.tags,
        });
      });
    });
  });
  return positionen;
}

/**
 * Stufe 1: exakt gleicher Schlüssel. Das fängt den Fall ab, für den der
 * Architekt-Prompt die Regel „wortgleich formulieren" mitbringt — und kostet
 * nichts.
 */
function gruppiereExakt(positionen: readonly Planposition[]): Bedarf[] {
  const nachSchluessel = new Map<string, Bedarf>();
  for (const pos of positionen) {
    const s = schluessel(pos.zweck, pos.tags);
    let bedarf = nachSchluessel.get(s);
    if (bedarf === undefined) {
      bedarf = {
        id: `b${nachSchluessel.size + 1}`,
        zweck: pos.zweck,
        tags: pos.tags,
        positionen: [],
      };
      nachSchluessel.set(s, bedarf);
    }
    bedarf.positionen.push({
      phase: pos.phase,
      einheit: pos.einheit,
      index: pos.index,
      // Bleibt pro Position erhalten: dieselbe Übung läuft in Phase 1 zehn
      // Minuten und in Phase 3 drei.
      dauer_min: pos.dauer_min,
    });
  }
  return [...nachSchluessel.values()];
}

/**
 * Stufe 2: was sich nur in der Formulierung unterscheidet, wird zusammengelegt.
 *
 * Bewusst gierig und in einem Durchgang: der erste Bedarf einer Gruppe gibt
 * Zweck und Tags vor. Ein richtiges Clustering wäre sauberer, würde bei den
 * zwanzig bis dreißig Bedarfen eines Plans aber kaum andere Gruppen finden.
 */
function legeAehnlicheZusammen(
  bedarfe: readonly Bedarf[],
  vektoren: readonly number[][],
): Bedarfsergebnis {
  const behalten: Bedarf[] = [];
  const behaltenVektoren: number[][] = [];

  bedarfe.forEach((bedarf, i) => {
    for (let k = 0; k < behalten.length; k++) {
      if (kosinus(vektoren[i], behaltenVektoren[k]) >= AEHNLICHKEIT_SCHWELLE) {
        behalten[k].positionen.push(...bedarf.positionen);
        return;
      }
    }
    behalten.push(bedarf);
    behaltenVektoren.push(vektoren[i]);
  });

  return {
    // Neu durchnummerieren, damit die IDs lückenlos bleiben.
    bedarfe: behalten.map((bedarf, i) => ({ ...bedarf, id: `b${i + 1}` })),
    vektoren: behaltenVektoren,
    positionen: 0,
  };
}

export interface Bedarfsergebnis {
  bedarfe: Bedarf[];
  /** Die Vektoren zu `bedarfe`, gleiche Reihenfolge. Das Retrieval sucht
   *  gleich damit weiter — ein zweiter Embedding-Aufruf für denselben Text
   *  wäre eine Unteranfrage, die niemandem nützt. */
  vektoren: number[][];
  /** Wie viele Positionen dahinterstehen — eine der Kennzahlen aus §11. */
  positionen: number;
}

export async function dampfeEin(
  env: Env,
  architektur: Architektur,
): Promise<Bedarfsergebnis> {
  const positionen = sammlePositionen(architektur);
  const exakt = gruppiereExakt(positionen);

  const vektoren = await bette(
    env,
    exakt.map((b) => bedarfstext(b.zweck, b.tags)),
  );
  const zusammengelegt = legeAehnlicheZusammen(exakt, vektoren);
  return { ...zusammengelegt, positionen: positionen.length };
}

/**
 * Rückweg: welcher Bedarf gehört zu welcher Position.
 *
 * Der Zusammenbau braucht das, um die Entscheidung des Kurators an alle
 * Positionen zurückzuschreiben, die den Bedarf hatten.
 */
export function positionsschluessel(phase: number, einheit: number, index: number): string {
  return `${phase}/${einheit}/${index}`;
}

export function bedarfJePosition(bedarfe: readonly Bedarf[]): Map<string, Bedarf> {
  const karte = new Map<string, Bedarf>();
  for (const bedarf of bedarfe) {
    for (const pos of bedarf.positionen) {
      karte.set(positionsschluessel(pos.phase, pos.einheit, pos.index), bedarf);
    }
  }
  return karte;
}
