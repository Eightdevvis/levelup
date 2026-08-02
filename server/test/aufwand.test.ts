import { describe, expect, it } from 'vitest';
import geige from '../grundstock/geige.json';
import { pruefeGrundstock, spieleEin, type Grundstockdatei } from '../src/grundstock';
import { fuehreAus } from '../src/pipeline';
import { nachrichtArchitekt, systemArchitekt } from '../src/prompts/architekt';
import { nachrichtDiagnose, systemDiagnose } from '../src/prompts/diagnose';
import type { Architektur, Eingabe, Phase, Problemmodell } from '../src/typen';
import { fakeAnthropic, type AntwortDoppel } from './hilfe';
import { fakeSpeicher } from './speicher';

/**
 * Was ein Lauf kostet.
 *
 * Zwei Zahlen entscheiden über den Zuschnitt: die Unteranfragen (Workers Free
 * erlaubt 50, Paid 10.000) und die Token. Beide werden hier an einem
 * realistischen Lauf gemessen statt geschätzt — 3 Phasen × 6 Einheiten × 4
 * Übungen, also 72 Positionen und zwölf eindeutige Bedarfe, gegen einen
 * Bestand aus dem echten Grundstock.
 *
 * Der Bericht landet in der Testausgabe. Der Test selbst hält nur fest, dass
 * die Größenordnung sich nicht unbemerkt verschiebt.
 */

const EINGABE: Eingabe = {
  vorhaben: 'Ich will Bach vom Blatt spielen können, nicht nur nach Gehör.',
  stand:
    'Sechs Jahre Unterricht als Kind, seitdem spiele ich nach Gehör. Blattspiel habe ich zweimal angefangen und wieder gelassen.',
  minuten_pro_tag: 45,
  tage_pro_woche: 5,
  equipment: 'Geige, Stimmgerät, Handy zum Aufnehmen, Notenständer, Metronom',
};

const PROBLEMMODELL: Problemmodell = {
  kernproblem:
    'Das Problem ist nicht Bach, sondern die Notation: die Zeichen werden gelesen und dann in Gehörwissen übersetzt, statt direkt in Griffe.',
  vermutete_ursache:
    'Das Gehör hat das Notenlesen jahrelang ersetzt, deshalb wurde die Zuordnung Zeichen zu Griff nie automatisch.',
  rueckkopplung: {
    quelle: 'vorlage',
    status: 'zu_spaet',
    begruendung:
      'Ob eine Stelle richtig war, merkt er erst am Klang — also nach dem Griff, nicht davor.',
  },
  vorbild: {
    wer: 'Orchestermusiker',
    methode:
      'Täglich kurze, unbekannte Stellen unter Tempo lesen und dabei nie anhalten, um sich zu korrigieren.',
  },
  grundfaehigkeiten: ['Notenbild in Griff übersetzen', 'Takt halten ohne Anhalten'],
  rueckfragen: [],
};

/** 3 Phasen × 6 Einheiten × 4 Übungen = 72 Positionen, 12 eindeutige Bedarfe. */
function grosserPlan(): Architektur {
  const zwecke = [
    { zweck: 'Vier Takte lesen und singen, ohne Instrument', tags: ['geige', 'notenlesen', 'gehoer'] },
    { zweck: 'Note lesen und sofort greifen, ohne zu prüfen', tags: ['geige', 'notenlesen', 'griff'] },
    { zweck: 'Unbekannte Stelle unter Tempo durchspielen', tags: ['geige', 'blattspiel', 'tempo'] },
    { zweck: 'Eigene Aufnahme gegen das Original hören', tags: ['geige', 'rueckkopplung', 'aufnahme'] },
    { zweck: 'Rhythmus klopfen, bevor gespielt wird', tags: ['geige', 'rhythmus'] },
    { zweck: 'Leersaiten gegen das Stimmgerät prüfen', tags: ['geige', 'stimmen', 'intonation'] },
    { zweck: 'Tonleiter über einem Bordunton spielen', tags: ['geige', 'intonation', 'tonleiter'] },
    { zweck: 'Bogenstrich im Spiegel führen', tags: ['geige', 'bogen', 'haltung'] },
    { zweck: 'Intervalle im Notenbild benennen', tags: ['geige', 'notenlesen', 'theorie'] },
    { zweck: 'Zwei Takte bis zur Gleichheit wiederholen', tags: ['geige', 'uebemethode'] },
    { zweck: 'Lagenwechsel ohne Hinsehen treffen', tags: ['geige', 'lagen', 'griff'] },
    {
      zweck: 'Stück nach einer Woche noch einmal aufnehmen',
      tags: ['geige', 'rueckkopplung', 'fortschritt'],
    },
  ];

  const phasen: Phase[] = [];
  for (let p = 0; p < 3; p++) {
    const einheiten = [];
    for (let e = 0; e < 6; e++) {
      einheiten.push({
        nummer: e + 1,
        // Vier Übungen je Einheit, rotierend über die zwölf Bedarfe.
        uebungen: [0, 1, 2, 3].map((i) => {
          const z = zwecke[(p * 6 + e + i * 3) % zwecke.length];
          return { zweck: z.zweck, tags: z.tags, dauer_min: 10 };
        }),
      });
    }
    phasen.push({
      titel: `Phase ${p + 1}`,
      ziel: 'Ziel der Phase, in einem Satz beschrieben.',
      austrittskriterium: 'Liest vier unbekannte Takte ohne Anhalten.',
      pruefung: 'Mitschnitt gegen das Original hören und die Abweichung benennen.',
      einheiten,
    });
  }

  return {
    programm_titel: 'Vom Gehör zum Blatt',
    programm_beschreibung:
      'Erst die Zuordnung Zeichen zu Griff automatisieren, dann Tempo, dann Bach.',
    phasen,
  };
}

function reuse(id: string): AntwortDoppel {
  return { text: { aktion: 'reuse', uebung_id: id, kontext_hinweis: 'Beginne unter Tempo.' } };
}

function erzeuge(nummer: number): AntwortDoppel {
  return {
    text: {
      aktion: 'create',
      kontext_hinweis: null,
      neue_uebung: {
        titel: `Neue Übung ${nummer}`,
        anleitung:
          'Lies die nächsten vier Takte, ohne zu spielen. Benenne für jeden Takt die erste Note. ' +
          'Spiel die Stelle danach einmal durch, ohne anzuhalten, auch wenn etwas danebengeht.',
        benefit: 'Du liest voraus, statt Note für Note nachzuziehen',
        tags: ['geige', 'notenlesen', `schwerpunkt${nummer}`],
        equipment: ['noten'],
        bild: null,
        animation: null,
      },
    },
  };
}

/** Grob, aber ehrlich: für deutschen Fließtext und JSON liegt Claudes
 *  Tokenizer bei etwa 3,5 Zeichen je Token. */
const ZEICHEN_JE_TOKEN = 3.5;

/** Was ein Denkgang vor einer Antwort ungefähr kostet. Nicht gemessen — der
 *  Doppelgänger denkt nicht. Bewusst großzügig angesetzt. */
const DENKTOKEN = { diagnose: 1200, architekt: 2500, kurator: 700 };

function token(text: string): number {
  return Math.round(text.length / ZEICHEN_JE_TOKEN);
}

const PREIS = { eingabe: 5 / 1_000_000, ausgabe: 25 / 1_000_000 };

describe('Aufwand eines Laufs', () => {
  it('zählt Unteranfragen und schätzt die Token', async () => {
    const s = fakeSpeicher();
    await spieleEin(s.env, pruefeGrundstock(geige) as Grundstockdatei);
    // Der Grundstock ist Vorbereitung, kein Lauf.
    s.zaehler.d1 = 0;
    s.zaehler.ai = 0;
    s.zaehler.vectorize = 0;

    // Vier von zwölf Bedarfen findet der Kurator im Bestand — eine
    // Wiederverwendungsquote von einem Drittel bei gefüllter Bibliothek.
    const antworten: AntwortDoppel[] = [
      reuse('g-geige-03'),
      erzeuge(1),
      erzeuge(2),
      reuse('g-geige-02'),
      erzeuge(3),
      reuse('g-geige-06'),
      erzeuge(4),
      erzeuge(5),
      erzeuge(6),
      reuse('g-geige-07'),
      erzeuge(7),
      erzeuge(8),
    ];
    const spion = fakeAnthropic(antworten);

    try {
      const architektur = grosserPlan();
      const ergebnis = await fuehreAus(s.env, {
        eingabe: EINGABE,
        problemmodell: PROBLEMMODELL,
        architektur,
        laufId: 'lauf-aufwand',
        deviceId: 'geraet-1',
      });

      // --- Unteranfragen ----------------------------------------------------
      // Was der Plan-Endpunkt außerhalb der Pipeline noch anfasst: Lauf laden,
      // Kontingent, Architektur merken, Kennzahlen, Lauf schließen, Übungen
      // laden, Tätigkeiten laden, Verbrauch buchen.
      const rahmenD1 = 8;
      const architektAufruf = 1;

      const d1 = s.zaehler.d1 + rahmenD1;
      const fetches = spion.aufrufe.length + architektAufruf;
      const eng = d1 + fetches;
      const weit = eng + s.zaehler.ai + s.zaehler.vectorize;

      // --- Token ------------------------------------------------------------
      // Was der Doppelgänger aufgezeichnet hat, sind die zwölf Kurator-Aufrufe.
      // Diagnose und Architekt laufen in eigenen Anfragen und werden hier aus
      // denselben Bausteinen zusammengesetzt, aus denen der Code sie baut.
      const kuratorEin = spion.aufrufe.reduce(
        (summe, a) =>
          summe +
          a.system.reduce((t, b) => t + b.text.length, 0) +
          JSON.stringify(a.messages).length,
        0,
      );
      const kuratorAus = antworten.reduce(
        (summe, a) => summe + JSON.stringify(a.text).length,
        0,
      );

      const diagnoseEin = token(systemDiagnose(false) + nachrichtDiagnose(EINGABE));
      const diagnoseAus = token(JSON.stringify(PROBLEMMODELL)) + DENKTOKEN.diagnose;

      const architektEin = token(
        systemArchitekt() + nachrichtArchitekt(PROBLEMMODELL, EINGABE),
      );
      // Der Plan selbst ist die längste Ausgabe des ganzen Laufs: 72 Positionen.
      const architektAus = token(JSON.stringify(architektur)) + DENKTOKEN.architekt;

      const eingabeToken = token(String.fromCharCode()) + diagnoseEin + architektEin +
        Math.round(kuratorEin / ZEICHEN_JE_TOKEN);
      const ausgabeToken =
        diagnoseAus +
        architektAus +
        Math.round(kuratorAus / ZEICHEN_JE_TOKEN) +
        DENKTOKEN.kurator * antworten.length;

      const kosten = eingabeToken * PREIS.eingabe + ausgabeToken * PREIS.ausgabe;

      console.log(
        '\n' +
          [
            '== Ein Lauf: 3 Phasen x 6 Einheiten x 4 Übungen ==',
            `Positionen            ${ergebnis.kennzahlen.uebungspositionen}`,
            `eindeutige Bedarfe    ${ergebnis.kennzahlen.bedarfe}`,
            `davon wiederverwendet ${ergebnis.kennzahlen.reuse}, neu ${ergebnis.kennzahlen.neu}`,
            '',
            '-- Unteranfragen der Plan-Anfrage --',
            `D1                    ${d1}`,
            `Anthropic (fetch)     ${fetches}`,
            `Workers AI            ${s.zaehler.ai}`,
            `Vectorize             ${s.zaehler.vectorize}`,
            `SUMME eng gezählt     ${eng}   (nur D1 + fetch, wie die Doku sie aufzählt)`,
            `SUMME weit gezählt    ${weit}   (alle Bindings)`,
            'Grenze Workers Free   50',
            'Grenze Workers Paid   10000',
            '',
            '-- Token (Texte gemessen, nur das Denken geschätzt) --',
            `Eingabe Diagnose      ${diagnoseEin}`,
            `Eingabe Architekt     ${architektEin}`,
            `Eingabe Kurator (12x) ${Math.round(kuratorEin / ZEICHEN_JE_TOKEN)}`,
            `Eingabe gesamt        ${eingabeToken}`,
            `Ausgabe gesamt        ${ausgabeToken}   (davon ${DENKTOKEN.diagnose + DENKTOKEN.architekt + DENKTOKEN.kurator * antworten.length} geschätztes Denken)`,
            `Kosten Opus 5         $${kosten.toFixed(2)}   ($5/M ein, $25/M aus)`,
            `mit Sonnet 5          $${(eingabeToken * 3e-6 + ausgabeToken * 15e-6).toFixed(2)}`,
          ].join('\n'),
      );

      expect(ergebnis.kennzahlen.uebungspositionen).toBe(72);
      expect(ergebnis.kennzahlen.bedarfe).toBe(12);
      // Der Punkt der ganzen Messung: Free reicht nicht, und zwar deutlich.
      expect(eng).toBeGreaterThan(50);
    } finally {
      spion.wiederherstellen();
    }
  });
});
