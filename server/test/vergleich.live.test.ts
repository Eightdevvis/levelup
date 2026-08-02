import { mkdirSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import geige from '../grundstock/geige.json';
import krafttraining from '../grundstock/krafttraining.json';
import { frage, leererVerbrauch, addiere, type Verbrauch } from '../src/anthropic';
import { normalisiereZweck } from '../src/bedarfe';
import { nachrichtArchitekt, systemArchitekt } from '../src/prompts/architekt';
import { nachrichtDiagnose, systemDiagnose } from '../src/prompts/diagnose';
import { nachrichtKurator, systemKurator, type Kuratorkontext } from '../src/prompts/kurator';
import {
  pruefeArchitektur,
  pruefeArchitekturRegeln,
  pruefeKuratorentscheidung,
  pruefeProblemmodell,
  type Ergebnis,
} from '../src/pruefen';
import type {
  Architektur,
  Eingabe,
  Kandidat,
  Kuratorentscheidung,
  Problemmodell,
} from '../src/typen';

/**
 * Opus gegen Sonnet, an denselben Aufgaben.
 *
 * Läuft gegen die echte API und kostet echtes Geld — deshalb übersprungen,
 * solange nicht ausdrücklich danach gefragt wird:
 *
 *   cd server
 *   ANTHROPIC_API_KEY=… VERGLEICH=1 npx vitest run test/vergleich.live.test.ts
 *
 * Grobe Kosten: rund 30 Aufrufe, zusammen etwa 1 bis 2 $.
 *
 * Der Schlüssel wird aus der Umgebung gelesen und nirgends hingeschrieben.
 * Die Ausgaben landen unter `vergleich/`, absichtlich **blind** beschriftet:
 * `modell-A` und `modell-B`, die Zuordnung getrennt in `zuordnung.json`. Wer
 * die Antworten liest, ohne vorher hineinzusehen, urteilt über den Text und
 * nicht über den Namen.
 */

const AKTIV = process.env.VERGLEICH === '1' && (process.env.ANTHROPIC_API_KEY ?? '') !== '';

/**
 * Wie oft jede Aufgabe wiederholt wird.
 *
 * Eins ist eine Stichprobe von eins: liegen zwei Modelle dann eng beieinander,
 * sagt das nichts. Zwei oder drei Runden zeigen wenigstens, ob ein Unterschied
 * größer ist als das Rauschen desselben Modells mit sich selbst. Kostet
 * entsprechend mehr.
 */
const RUNDEN = Math.max(1, Number(process.env.VERGLEICH_RUNDEN ?? '1'));

const MODELLE = ['claude-opus-5', 'claude-sonnet-5'] as const;

/** Preise je Million Token: [Eingabe, Ausgabe]. */
const PREISE: Record<string, [number, number]> = {
  'claude-opus-5': [5, 25],
  'claude-sonnet-5': [3, 15],
};

// --- Die Aufgaben ----------------------------------------------------------

interface Aufgabe {
  name: string;
  eingabe: Eingabe;
  /** Ob es zu dieser Tätigkeit Bausteine im Grundstock gibt. */
  imBestand: boolean;
}

const AUFGABEN: Aufgabe[] = [
  {
    name: '1-geige-blattspiel',
    imBestand: true,
    eingabe: {
      vorhaben: 'Ich will Bach vom Blatt spielen können, nicht nur nach Gehör.',
      stand:
        'Sechs Jahre Unterricht als Kind, seitdem spiele ich nach Gehör und lerne Stücke auswendig. Blattspiel habe ich zweimal angefangen und wieder gelassen, weil ich beim Lesen ständig anhalten muss.',
      minuten_pro_tag: 45,
      tage_pro_woche: 5,
      equipment: 'Geige, Stimmgerät, Handy zum Aufnehmen, Notenständer, Metronom, Notenhefte',
    },
  },
  {
    name: '2-kraft-kniebeuge',
    imBestand: true,
    eingabe: {
      vorhaben: 'Ich will eine saubere tiefe Kniebeuge mit Langhantel.',
      stand:
        'Ich trainiere seit einem Jahr, komme aber nicht tief und mein Rücken rundet sich unten. Gefühlt ist alles in Ordnung, auf Videos sieht es anders aus.',
      minuten_pro_tag: 60,
      tage_pro_woche: 3,
      equipment: 'Fitnessstudio mit Langhantel, Rack, Boxen, Handy zum Filmen, Trainingspartner',
    },
  },
  {
    name: '3-fremde-taetigkeit',
    // Kein Grundstock zu dieser Tätigkeit. Der Kurator bekommt trotzdem
    // Geigen- und Kraft-Bausteine vorgelegt — die Falle aus §8: „Kandidaten
    // aus einer anderen Tätigkeit passen nicht, auch wenn sie ähnlich
    // klingen."
    imBestand: false,
    eingabe: {
      vorhaben: 'Ich will frei vor Publikum sprechen können, ohne Skript.',
      stand:
        'Ich halte im Job regelmäßig Vorträge, lese sie aber praktisch ab. Sobald ich vom Text abweiche, verliere ich den Faden und rede mich in Schachtelsätze hinein.',
      minuten_pro_tag: 20,
      tage_pro_woche: 4,
      equipment: 'Handy zum Aufnehmen, ein Kollege, der zuhören würde, ein leerer Besprechungsraum',
    },
  },
];

/** Alle 24 Grundstock-Bausteine als Kandidatenliste. */
const KANDIDATEN: Kandidat[] = [...geige.bausteine, ...krafttraining.bausteine].map((b) => ({
  id: b.id,
  titel: b.titel,
  anleitung: b.anleitung,
  benefit: b.benefit,
  tags: b.tags,
  equipment: b.equipment,
}));

const TAETIGKEITS_TAGS = new Set(['geige', 'krafttraining']);

// --- Messung ---------------------------------------------------------------

interface Schrittbefund {
  schritt: string;
  /** Wie oft die Ausgabe der Prüfung nicht standhielt. Das härteste Signal:
   *  es kostet eine ganze zusätzliche Runde und ist nicht Geschmackssache. */
  nachbesserungen: number;
  /** Was genau beanstandet wurde — die interessantere Hälfte. */
  beanstandungen: string[];
  abgebrochen: boolean;
  sekunden: number;
  verbrauch: Verbrauch;
}

interface Modellbefund {
  modell: string;
  aufgabe: string;
  schritte: Schrittbefund[];
  problemmodell: Problemmodell | null;
  architektur: Architektur | null;
  kuratorentscheidungen: { zweck: string; entscheidung: Kuratorentscheidung | null }[];
  /** Wie oft der Kurator einen Baustein aus einer fremden Tätigkeit nahm. */
  fachfremdeUebernahmen: number;
  wiederverwendet: number;
  neuErzeugt: number;
}

function env(modell: string): Env {
  return {
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    MODELL_DIAGNOSE: modell,
    MODELL_ARCHITEKT: modell,
    MODELL_KURATOR: modell,
  } as unknown as Env;
}

/**
 * Führt einen Schritt aus und zeichnet auf, was dabei schiefging.
 *
 * Die Prüffunktion wird umhüllt statt ersetzt: so zählt der Befund genau die
 * Beanstandungen, die auch im Betrieb eine Nachbesserung ausgelöst hätten.
 */
async function messe<T>(
  schritt: string,
  modell: string,
  system: string,
  nachricht: string,
  maxTokens: number,
  pruefe: (roh: unknown) => Ergebnis<T>,
): Promise<{ befund: Schrittbefund; wert: T | null }> {
  const beanstandungen: string[] = [];
  const start = Date.now();

  const umhuellt = (roh: unknown): Ergebnis<T> => {
    const ergebnis = pruefe(roh);
    if (!ergebnis.ok) beanstandungen.push(...ergebnis.fehler);
    return ergebnis;
  };

  let nachbesserungen = 0;
  let abgebrochen = false;
  let wert: T | null = null;
  const verbrauch = leererVerbrauch();

  try {
    const antwort = await frage<T>(env(modell), {
      system,
      nachricht,
      modell,
      maxTokens,
      pruefe: umhuellt,
      melde: (e) => {
        if (e.type === 'repair') nachbesserungen++;
      },
      zeigeGedanken: false,
    });
    wert = antwort.wert;
    addiere(verbrauch, antwort.verbrauch);
  } catch (fehler) {
    abgebrochen = true;
    beanstandungen.push(`ABBRUCH: ${fehler instanceof Error ? fehler.message : String(fehler)}`);
  }

  return {
    befund: {
      schritt,
      nachbesserungen,
      beanstandungen,
      abgebrochen,
      sekunden: Math.round((Date.now() - start) / 100) / 10,
      verbrauch,
    },
    wert,
  };
}

async function laufe(modell: string, aufgabe: Aufgabe): Promise<Modellbefund> {
  const befund: Modellbefund = {
    modell,
    aufgabe: aufgabe.name,
    schritte: [],
    problemmodell: null,
    architektur: null,
    kuratorentscheidungen: [],
    fachfremdeUebernahmen: 0,
    wiederverwendet: 0,
    neuErzeugt: 0,
  };

  // [1] Diagnose
  const diagnose = await messe(
    'diagnose',
    modell,
    systemDiagnose(false),
    nachrichtDiagnose(aufgabe.eingabe),
    4000,
    pruefeProblemmodell,
  );
  befund.schritte.push(diagnose.befund);
  befund.problemmodell = diagnose.wert;
  if (diagnose.wert === null) return befund;

  // [2] Architekt — Schema und Prompt-Regeln in einem Durchgang, genau wie
  // im Betrieb.
  const architekt = await messe(
    'architekt',
    modell,
    systemArchitekt(),
    nachrichtArchitekt(diagnose.wert, aufgabe.eingabe),
    16000,
    (roh): Ergebnis<Architektur> => {
      const geprueft = pruefeArchitektur(roh);
      if (!geprueft.ok) return geprueft;
      const verstoesse = pruefeArchitekturRegeln(geprueft.wert, aufgabe.eingabe.minuten_pro_tag);
      return verstoesse.length === 0 ? geprueft : { ok: false, fehler: verstoesse };
    },
  );
  befund.schritte.push(architekt.befund);
  befund.architektur = architekt.wert;
  if (architekt.wert === null) return befund;

  // [4] Kurator, für die ersten drei eindeutigen Bedarfe. Ohne Retrieval:
  // beide Modelle bekommen denselben Bestand vorgelegt, damit der Unterschied
  // an der Entscheidung hängt und nicht an der Suche.
  const gesehen = new Set<string>();
  const bedarfe = architekt.wert.phasen
    .flatMap((phase, p) =>
      phase.einheiten.flatMap((einheit, e) =>
        einheit.uebungen.map((u, i) => ({ ...u, phase, p, e, i })),
      ),
    )
    .filter((u) => {
      const schluessel = normalisiereZweck(u.zweck);
      if (gesehen.has(schluessel)) return false;
      gesehen.add(schluessel);
      return true;
    })
    .slice(0, 3);

  for (const bedarf of bedarfe) {
    const kontext: Kuratorkontext = {
      eingabe: aufgabe.eingabe,
      problemmodell: diagnose.wert,
      phase: bedarf.phase,
      bedarf: {
        id: 'b',
        zweck: bedarf.zweck,
        tags: bedarf.tags,
        positionen: [{ phase: bedarf.p, einheit: bedarf.e, index: bedarf.i, dauer_min: bedarf.dauer_min }],
      },
      dauerMin: bedarf.dauer_min,
      bereitsInEinheit: [],
      bereitsGeplant: [],
      kandidaten: KANDIDATEN,
    };

    const kurator = await messe(
      `kurator: ${bedarf.zweck}`,
      modell,
      systemKurator(),
      nachrichtKurator(kontext),
      4000,
      (roh) => pruefeKuratorentscheidung(roh, KANDIDATEN.map((k) => k.id)),
    );
    befund.schritte.push(kurator.befund);
    befund.kuratorentscheidungen.push({ zweck: bedarf.zweck, entscheidung: kurator.wert });

    const entscheidung = kurator.wert;
    if (entscheidung === null) continue;
    if (entscheidung.aktion === 'reuse') {
      befund.wiederverwendet++;
      // Die Falle aus §8: bei einer Tätigkeit ohne Bestand ist *jede*
      // Wiederverwendung fachfremd.
      const genommen = KANDIDATEN.find((k) => k.id === entscheidung.uebung_id);
      const fremd =
        !aufgabe.imBestand ||
        (genommen !== undefined &&
          !genommen.tags.some((t) => TAETIGKEITS_TAGS.has(t) && bedarf.tags.includes(t)));
      if (fremd) befund.fachfremdeUebernahmen++;
    } else {
      befund.neuErzeugt++;
    }
  }

  return befund;
}

// --- Bericht ---------------------------------------------------------------

function kosten(modell: string, v: Verbrauch): number {
  const [ein, aus] = PREISE[modell] ?? [0, 0];
  return ((v.input + v.cacheRead + v.cacheWrite) * ein + v.output * aus) / 1_000_000;
}

function bericht(befunde: Modellbefund[], etikett: string): string {
  const zeilen: string[] = [`# Modell ${etikett}`, ''];

  for (const b of befunde) {
    const v = leererVerbrauch();
    for (const s of b.schritte) addiere(v, s.verbrauch);

    zeilen.push(
      `## Aufgabe ${b.aufgabe}`,
      '',
      `- Nachbesserungen: ${b.schritte.reduce((s, x) => s + x.nachbesserungen, 0)}`,
      `- Abbrüche: ${b.schritte.filter((x) => x.abgebrochen).length}`,
      `- Kurator: ${b.wiederverwendet}x wiederverwendet, ${b.neuErzeugt}x neu`,
      `- davon fachfremd übernommen: ${b.fachfremdeUebernahmen}`,
      `- Dauer: ${b.schritte.reduce((s, x) => s + x.sekunden, 0).toFixed(1)} s`,
      `- Token: ${v.input + v.cacheRead + v.cacheWrite} ein / ${v.output} aus`,
      '',
    );

    const beanstandet = b.schritte.filter((s) => s.beanstandungen.length > 0);
    if (beanstandet.length > 0) {
      zeilen.push('### Was die Prüfung beanstandet hat', '');
      for (const s of beanstandet) {
        zeilen.push(`**${s.schritt}**`, ...s.beanstandungen.map((f) => `- ${f}`), '');
      }
    }

    zeilen.push('### Problemmodell', '', '```json', JSON.stringify(b.problemmodell, null, 2), '```', '');
    zeilen.push('### Architektur', '', '```json', JSON.stringify(b.architektur, null, 2), '```', '');
    zeilen.push('### Kuratorentscheidungen', '');
    for (const e of b.kuratorentscheidungen) {
      zeilen.push(`**${e.zweck}**`, '', '```json', JSON.stringify(e.entscheidung, null, 2), '```', '');
    }
  }

  return zeilen.join('\n');
}

describe.skipIf(!AKTIV)('Opus gegen Sonnet', () => {
  it(
    'läuft beide Modelle über dieselben Aufgaben',
    async () => {
      const alle = new Map<string, Modellbefund[]>();

      for (const modell of MODELLE) {
        const befunde: Modellbefund[] = [];
        for (let runde = 1; runde <= RUNDEN; runde++) {
          for (const aufgabe of AUFGABEN) {
            const name = RUNDEN === 1 ? aufgabe.name : `${aufgabe.name} (Runde ${runde})`;
            console.log(`… ${modell} / ${name}`);
            const ergebnis = await laufe(modell, aufgabe);
            befunde.push({ ...ergebnis, aufgabe: name });
          }
        }
        alle.set(modell, befunde);
      }

      // Blind beschriften: welches Etikett welches Modell trägt, steht nur in
      // der Zuordnungsdatei.
      const gemischt = [...MODELLE].sort(() => (Math.random() < 0.5 ? -1 : 1));
      const etiketten = ['A', 'B'];

      mkdirSync('vergleich', { recursive: true });
      const zuordnung: Record<string, string> = {};
      const zusammenfassung: string[] = [
        '| Modell | Aufgabe | Nachbess. | Abbrüche | reuse | neu | fachfremd | Dauer s | Kosten $ |',
        '|---|---|---|---|---|---|---|---|---|',
      ];

      gemischt.forEach((modell, i) => {
        const etikett = etiketten[i];
        zuordnung[etikett] = modell;
        const befunde = alle.get(modell) ?? [];
        writeFileSync(`vergleich/modell-${etikett}.md`, bericht(befunde, etikett));

        for (const b of befunde) {
          const v = leererVerbrauch();
          for (const s of b.schritte) addiere(v, s.verbrauch);
          zusammenfassung.push(
            `| ${etikett} | ${b.aufgabe} | ${b.schritte.reduce((s, x) => s + x.nachbesserungen, 0)} ` +
              `| ${b.schritte.filter((x) => x.abgebrochen).length} | ${b.wiederverwendet} ` +
              `| ${b.neuErzeugt} | ${b.fachfremdeUebernahmen} ` +
              `| ${b.schritte.reduce((s, x) => s + x.sekunden, 0).toFixed(1)} ` +
              `| ${kosten(modell, v).toFixed(3)} |`,
          );
        }
      });

      writeFileSync('vergleich/zuordnung.json', JSON.stringify(zuordnung, null, 2));
      writeFileSync('vergleich/zahlen.md', zusammenfassung.join('\n'));
      console.log('\n' + zusammenfassung.join('\n'));
      console.log(
        '\nBerichte: server/vergleich/modell-A.md und modell-B.md' +
          '\nWer welches ist: server/vergleich/zuordnung.json (erst danach aufmachen)',
      );

      expect(alle.size).toBe(MODELLE.length);
    },
    // Fünfzehn Aufrufe je Modell und Runde, viele davon mit langem Denken.
    // Die Vorgabe von fünf Sekunden reicht nicht annähernd.
    RUNDEN * 45 * 60 * 1000,
  );
});
