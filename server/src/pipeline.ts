import { addiere, leererVerbrauch, type Verbrauch } from './anthropic';
import { bedarfJePosition, dampfeEin, positionsschluessel } from './bedarfe';
import { ladeKandidaten } from './bibliothek';
import type { Melder } from './ereignisse';
import { kuratiere, type Geplant, type Kuratorkontext } from './prompts/kurator';
import { sucheKandidaten } from './retrieval';
import { verarbeiteEntscheidung } from './speichern';
import type {
  Architektur,
  Bedarf,
  Eingabe,
  Kandidat,
  Kennzahlen,
  Kuratorentscheidung,
  Position,
  Problemmodell,
  Uebungsreferenz,
} from './typen';

/**
 * Die Schritte [3] bis [5] am Stück.
 *
 * Sequenziell über die Bedarfe, nicht parallel: §9 verlangt, dass ein später
 * verarbeiteter Bedarf die neuen Bausteine desselben Laufs schon als
 * Kandidaten sieht. Parallel wäre schneller und würde genau den Zustand
 * herstellen, den das Dedupe verhindern soll.
 */

export interface Planergebnis {
  /** Je Position im Plan die Übung, die dort steht. Schlüssel wie in
   *  `positionsschluessel`. */
  referenzen: Map<string, Uebungsreferenz>;
  kennzahlen: Kennzahlen;
  verbrauch: Verbrauch;
}

export interface Pipelineauftrag {
  eingabe: Eingabe;
  problemmodell: Problemmodell;
  architektur: Architektur;
  laufId: string;
  deviceId: string;
  melde?: Melder;
}

/** Die Position, an der ein Bedarf zuerst vorkommt. Sie gibt Phase, Einheit
 *  und Dauer für den Kuratoraufruf vor (§8). */
function fruehestePosition(bedarf: Bedarf): Position {
  return bedarf.positionen.reduce((a, b) =>
    a.phase !== b.phase
      ? a.phase < b.phase
        ? a
        : b
      : a.einheit !== b.einheit
        ? a.einheit < b.einheit
          ? a
          : b
        : a.index <= b.index
          ? a
          : b,
  );
}

export async function fuehreAus(env: Env, auftrag: Pipelineauftrag): Promise<Planergebnis> {
  const verbrauch = leererVerbrauch();
  const melde = auftrag.melde;

  melde?.({ type: 'schritt', name: 'bedarfe' });
  const { bedarfe, vektoren, positionen } = await dampfeEin(env, auftrag.architektur);
  const jePosition = bedarfJePosition(bedarfe);

  const kennzahlen: Kennzahlen = {
    bedarfe: bedarfe.length,
    reuse: 0,
    neu: 0,
    neue_tags: 0,
    pruefliste: 0,
    uebungspositionen: positionen,
  };

  /** Was an einer Position steht, sobald ihr Bedarf entschieden ist. */
  const referenzen = new Map<string, Uebungsreferenz>();
  /** Titel und Tags je entschiedenem Bedarf — Futter für `bereits_geplant`. */
  const entschieden = new Map<string, Geplant>();

  for (let i = 0; i < bedarfe.length; i++) {
    const bedarf = bedarfe[i];
    const start = fruehestePosition(bedarf);
    const phase = auftrag.architektur.phasen[start.phase];

    melde?.({ type: 'schritt', name: 'retrieval', fertig: i, gesamt: bedarfe.length });
    const kandidaten = await sucheKandidaten(env, bedarf, vektoren[i], melde);

    const kontext: Kuratorkontext = {
      eingabe: auftrag.eingabe,
      problemmodell: auftrag.problemmodell,
      phase,
      bedarf,
      dauerMin: start.dauer_min,
      bereitsInEinheit: titelDerEinheit(start, jePosition, entschieden),
      bereitsGeplant: [...entschieden.values()],
      kandidaten,
    };

    melde?.({ type: 'schritt', name: 'kurator', fertig: i, gesamt: bedarfe.length });
    const antwort = await kuratiere(env, kontext, melde);
    addiere(verbrauch, antwort.verbrauch);

    melde?.({ type: 'schritt', name: 'speichern', fertig: i, gesamt: bedarfe.length });
    const gespeichert = await verarbeiteEntscheidung(env, antwort.wert, {
      laufId: auftrag.laufId,
      deviceId: auftrag.deviceId,
    });

    if (gespeichert.neu) kennzahlen.neu++;
    else kennzahlen.reuse++;
    if (gespeichert.zurPruefung) kennzahlen.pruefliste++;
    kennzahlen.neue_tags += gespeichert.neueTags.length;

    entschieden.set(
      bedarf.id,
      await beschreibe(
        env,
        gespeichert.uebung_id,
        antwort.wert,
        kandidaten,
        gespeichert.zurPruefung,
      ),
    );

    // Die Entscheidung gilt für alle Positionen dieses Bedarfs — die Dauer
    // bleibt aber die der jeweiligen Position.
    for (const pos of bedarf.positionen) {
      referenzen.set(positionsschluessel(pos.phase, pos.einheit, pos.index), {
        uebung_id: gespeichert.uebung_id,
        dauer_min: pos.dauer_min,
        kontext_hinweis: gespeichert.kontext_hinweis,
      });
    }
  }

  return { referenzen, kennzahlen, verbrauch };
}

/**
 * Titel der Übungen, die in derselben Einheit schon feststehen.
 *
 * Wir laufen die Bedarfe in der Reihenfolge ihres ersten Vorkommens ab, also
 * ist alles links davon in derselben Einheit bereits entschieden.
 */
function titelDerEinheit(
  start: Position,
  jePosition: Map<string, Bedarf>,
  entschieden: Map<string, Geplant>,
): string[] {
  const titel: string[] = [];
  for (let index = 0; index < start.index; index++) {
    const bedarf = jePosition.get(positionsschluessel(start.phase, start.einheit, index));
    const fertig = bedarf === undefined ? undefined : entschieden.get(bedarf.id);
    if (fertig !== undefined) titel.push(fertig.titel);
  }
  return titel;
}

/**
 * Titel und Tags dessen, was an dieser Stelle nun wirklich steht.
 *
 * Meist steht es schon da: bei `reuse` in der Kandidatenliste, bei `create` im
 * neuen Baustein. Nur wenn das Dedupe auf einen Bestandsbaustein umgelenkt hat,
 * der nicht unter den Kandidaten war, wird eine Zeile nachgeladen — selten
 * genug, dass die eine Abfrage nicht ins Gewicht fällt.
 */
async function beschreibe(
  env: Env,
  uebungId: string,
  entscheidung: Kuratorentscheidung,
  kandidaten: readonly Kandidat[],
  zurPruefung: boolean,
): Promise<Geplant> {
  const ausListe = kandidaten.find((k) => k.id === uebungId);
  if (ausListe !== undefined) return { titel: ausListe.titel, tags: ausListe.tags };

  // Ohne Umlenkung durch das Dedupe steht der neue Baustein genau so da, wie
  // der Kurator ihn geschrieben hat.
  if (entscheidung.aktion === 'create' && !zurPruefung) {
    return { titel: entscheidung.neue_uebung.titel, tags: entscheidung.neue_uebung.tags };
  }

  const [zeile] = await ladeKandidaten(env, [uebungId]);
  return zeile === undefined
    ? { titel: uebungId, tags: [] }
    : { titel: zeile.titel, tags: zeile.tags };
}
