import { afterEach, describe, expect, it } from 'vitest';
import { ladeUebungen } from '../src/bibliothek';
import { baueBundle, verteile } from '../src/bundle';
import { fuehreAus } from '../src/pipeline';
import type { Architektur, Eingabe, NeueUebung, Problemmodell } from '../src/typen';
import { fakeAnthropic, type Spion } from './hilfe';
import { fakeSpeicher } from './speicher';

const EINGABE: Eingabe = {
  vorhaben: 'Geige spielen',
  stand: 'Zwei Jahre Unterricht als Kind',
  minuten_pro_tag: 30,
  tage_pro_woche: 3,
  equipment: 'Geige, Handy',
};

const PROBLEMMODELL: Problemmodell = {
  kernproblem: 'Die Intonation wird nicht gehört, nur gefühlt.',
  vermutete_ursache: 'Kein Abgleich mit einem äußeren Ton.',
  rueckkopplung: { quelle: 'vorlage', status: 'fehlt', begruendung: 'Kein Referenzton beim Üben.' },
  vorbild: { wer: 'Orchestermusiker', methode: 'Täglich gegen Bordunton stimmen.' },
  grundfaehigkeiten: ['Tonhöhen unterscheiden'],
  rueckfragen: [],
};

/** Zwei Phasen, je zwei Einheiten, je drei Übungen — zwölf Positionen, aber
 *  nur vier verschiedene Bedarfe. Genau der Fall aus §7.1. */
function plan(): Architektur {
  const zwecke = [
    { zweck: 'Eigene Aufnahme anhören', tags: ['geige', 'aufnahme'] },
    { zweck: 'Ton gegen Bordun abgleichen', tags: ['geige', 'intonation'] },
    { zweck: 'Bogen gleichmäßig führen', tags: ['geige', 'bogen'] },
    { zweck: 'Leersaiten stimmen', tags: ['geige', 'stimmen'] },
  ];

  const einheit = (a: number, b: number, c: number) => ({
    nummer: 1,
    uebungen: [a, b, c].map((i) => ({ ...zwecke[i], dauer_min: 10 })),
  });

  return {
    programm_titel: 'Gehör zuerst',
    programm_beschreibung: 'Erst hören lernen, dann spielen.',
    phasen: [
      {
        titel: 'Rückkopplung aufbauen',
        ziel: 'Eigene Intonation hörbar machen',
        austrittskriterium: 'Erkennt abweichende Töne im Mitschnitt',
        pruefung: 'Aufnahme gegen den Bordunton',
        einheiten: [einheit(0, 1, 3), einheit(0, 1, 2)],
      },
      {
        titel: 'Festigen',
        ziel: 'Sauber spielen ohne Kontrolle',
        austrittskriterium: 'Spielt drei Durchgänge gleich',
        pruefung: 'Drei Aufnahmen nebeneinander hören',
        einheiten: [einheit(1, 2, 3), einheit(0, 2, 3)],
      },
    ],
  };
}

const BESTAND: NeueUebung & { id: string } = {
  id: 'u-bestand',
  titel: 'Acht Takte aufnehmen und anhören',
  anleitung: 'Nimm die schwierigste Stelle auf.\nHör sie einmal ganz durch.',
  benefit: 'Du bemerkst Fehler, die du im Spielen nicht hörst',
  tags: ['geige', 'rueckkopplung', 'aufnahme'],
  equipment: ['aufnahmegeraet'],
  bild: null,
  animation: null,
};

function erzeuge(titel: string, tags: string[]) {
  return {
    aktion: 'create',
    kontext_hinweis: null,
    neue_uebung: {
      titel,
      anleitung: `Anleitung zu ${titel}.`,
      benefit: `Wirkung von ${titel}`,
      tags,
      equipment: [],
      bild: null,
      animation: null,
    },
  };
}

let spion: Spion | null = null;
afterEach(() => {
  spion?.wiederherstellen();
  spion = null;
});

describe('Pipeline [3] bis [5]', () => {
  it('entscheidet einmal je Bedarf und schreibt an alle Positionen zurück', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);

    spion = fakeAnthropic([
      { text: { aktion: 'reuse', uebung_id: 'u-bestand', kontext_hinweis: 'Beginne langsam' } },
      { text: erzeuge('Ton gegen Bordun halten', ['geige', 'intonation', 'gehoer']) },
      { text: erzeuge('Bogen im Spiegel führen', ['geige', 'bogen', 'haltung']) },
      { text: erzeuge('Leersaiten nach Gehör stimmen', ['geige', 'stimmen', 'gehoer']) },
    ]);

    const ergebnis = await fuehreAus(s.env, {
      eingabe: EINGABE,
      problemmodell: PROBLEMMODELL,
      architektur: plan(),
      laufId: 'lauf-1',
      deviceId: 'geraet-1',
    });

    // Vier Aufrufe für zwölf Positionen — das ist der Sinn von §7.1.
    expect(spion.aufrufe).toHaveLength(4);
    expect(ergebnis.kennzahlen).toMatchObject({
      bedarfe: 4,
      reuse: 1,
      neu: 3,
      pruefliste: 0,
      uebungspositionen: 12,
    });
    expect(ergebnis.referenzen.size).toBe(12);
    // Der Bestandsbaustein steht an allen drei Stellen, an denen der Bedarf
    // „Eigene Aufnahme anhören" vorkam.
    const mitBestand = [...ergebnis.referenzen.values()].filter(
      (r) => r.uebung_id === 'u-bestand',
    );
    expect(mitBestand).toHaveLength(3);
    expect(mitBestand[0].kontext_hinweis).toBe('Beginne langsam');
  });

  it('zeigt dem Kurator, was in dieser Einheit schon steht', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);
    spion = fakeAnthropic([
      { text: { aktion: 'reuse', uebung_id: 'u-bestand', kontext_hinweis: null } },
      { text: erzeuge('Ton gegen Bordun halten', ['geige', 'intonation']) },
      { text: erzeuge('Bogen im Spiegel führen', ['geige', 'bogen']) },
      { text: erzeuge('Leersaiten nach Gehör stimmen', ['geige', 'stimmen']) },
    ]);

    await fuehreAus(s.env, {
      eingabe: EINGABE,
      problemmodell: PROBLEMMODELL,
      architektur: plan(),
      laufId: 'lauf-1',
      deviceId: 'geraet-1',
    });

    const zweiter = String(spion.aufrufe[1].messages[0].content);
    expect(zweiter).toContain('Acht Takte aufnehmen und anhören');

    // bereits_geplant wächst, trägt aber nur Titel und Tags.
    const vierter = String(spion.aufrufe[3].messages[0].content);
    const block = vierter.slice(
      vierter.indexOf('<bereits_geplant>'),
      vierter.indexOf('</bereits_geplant>'),
    );
    expect(block).toContain('Ton gegen Bordun halten [geige, intonation]');
    expect(block).not.toContain('Anleitung zu');
  });

  it('lässt den neuen Baustein des ersten Bedarfs beim zweiten schon sehen', async () => {
    // Beide Bedarfe brauchen dasselbe; der Kurator schlägt zweimal etwas
    // Neues vor. Das Dedupe fängt es ab — aber nur, weil sequenziell
    // gespeichert wird.
    const s = fakeSpeicher({
      'Bogen im Spiegel führen': [1, 0, 0.02],
      'Bogenführung am Spiegel': [1, 0.02, 0],
    });
    spion = fakeAnthropic([
      { text: erzeuge('Bogen im Spiegel führen', ['geige', 'bogen']) },
      { text: erzeuge('Bogenführung am Spiegel', ['geige', 'bogen']) },
      { text: erzeuge('Dritter Baustein', ['geige', 'sonstiges']) },
      { text: erzeuge('Vierter Baustein', ['geige', 'sonstiges']) },
    ]);

    const ergebnis = await fuehreAus(s.env, {
      eingabe: EINGABE,
      problemmodell: PROBLEMMODELL,
      architektur: plan(),
      laufId: 'lauf-1',
      deviceId: 'geraet-1',
    });

    expect(ergebnis.kennzahlen.neu).toBe(3);
    expect(ergebnis.kennzahlen.pruefliste).toBe(1);
    expect(s.pruefliste).toHaveLength(1);
  });
});

describe('Bundle (Arbeitsliste 10)', () => {
  it('baut aus dem Pipeline-Ergebnis ein Bundle ohne offene Verweise', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);
    spion = fakeAnthropic([
      { text: { aktion: 'reuse', uebung_id: 'u-bestand', kontext_hinweis: 'Beginne langsam' } },
      { text: erzeuge('Ton gegen Bordun halten', ['geige', 'intonation']) },
      { text: erzeuge('Bogen im Spiegel führen', ['geige', 'bogen']) },
      { text: erzeuge('Leersaiten nach Gehör stimmen', ['geige', 'stimmen']) },
    ]);

    const architektur = plan();
    const ergebnis = await fuehreAus(s.env, {
      eingabe: EINGABE,
      problemmodell: PROBLEMMODELL,
      architektur,
      laufId: 'lauf-1',
      deviceId: 'geraet-1',
    });

    const ids = [...new Set([...ergebnis.referenzen.values()].map((r) => r.uebung_id))];
    const bundle = baueBundle({
      architektur,
      referenzen: ergebnis.referenzen,
      uebungen: await ladeUebungen(s.env, ids),
      problemmodell: PROBLEMMODELL,
      eingabe: EINGABE,
      programmId: 'prog-1',
      taetigkeiten: new Set(['geige']),
    });

    // Jeder Slot zeigt auf eine Übung, die im selben Bundle liegt.
    const vorhanden = new Set(bundle.exercises.map((e) => e.id));
    const offen = bundle.routines
      .flatMap((r) => r.slots.map((sl) => sl.exerciseId))
      .filter((id) => !vorhanden.has(id));
    expect(offen).toEqual([]);

    // Und jede Routine, auf die ein Phasenplan zeigt, existiert.
    const routinen = new Set(bundle.routines.map((r) => r.id));
    const offeneRoutinen = bundle.programs[0].phases
      .flatMap((p) => p.schedule.days.map((d) => d.routineId))
      .filter((id): id is string => id !== undefined && !routinen.has(id));
    expect(offeneRoutinen).toEqual([]);

    expect(bundle.routines).toHaveLength(4);
    expect(bundle.programs[0].name).toBe('Gehör zuerst');
    // Kein domain-Feld: die Tätigkeit steht als erster Tag.
    expect(bundle.programs[0].tags[0]).toBe('geige');
  });

  it('übersetzt die Felder, wie Arbeitsliste 10 es vorgibt', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);
    spion = fakeAnthropic([
      { text: { aktion: 'reuse', uebung_id: 'u-bestand', kontext_hinweis: 'Erst nach dem Stimmen' } },
      { text: erzeuge('A', ['geige', 'intonation']) },
      { text: erzeuge('B', ['geige', 'bogen']) },
      { text: erzeuge('C', ['geige', 'stimmen']) },
    ]);

    const architektur = plan();
    const ergebnis = await fuehreAus(s.env, {
      eingabe: EINGABE,
      problemmodell: PROBLEMMODELL,
      architektur,
      laufId: 'lauf-1',
      deviceId: 'geraet-1',
    });
    const ids = [...new Set([...ergebnis.referenzen.values()].map((r) => r.uebung_id))];
    const bundle = baueBundle({
      architektur,
      referenzen: ergebnis.referenzen,
      uebungen: await ladeUebungen(s.env, ids),
      problemmodell: PROBLEMMODELL,
      eingabe: EINGABE,
      programmId: 'prog-1',
      taetigkeiten: new Set(['geige']),
    });

    const bestand = bundle.exercises.find((e) => e.id === 'u-bestand');
    expect(bestand?.name).toBe('Acht Takte aufnehmen und anhören');
    // Die Anleitung bleibt ein Feld — geteilt wird erst beim Anzeigen.
    expect(bestand?.description).toBe(
      'Nimm die schwierigste Stelle auf.\nHör sie einmal ganz durch.',
    );
    expect(bestand?.benefits).toEqual(['Du bemerkst Fehler, die du im Spielen nicht hörst']);
    expect(bestand?.equipment).toEqual(['aufnahmegeraet']);
    // Kein domain-Feld mehr: die Tätigkeit steht als erster Tag.
    expect(bestand?.tags[0]).toBe('geige');

    const slot = bundle.routines[0].slots[0];
    expect(slot.sets).toEqual([{ target: { kind: 'duration', seconds: 600 } }]);
    expect(slot.note).toBe('Erst nach dem Stimmen');

    const phase = bundle.programs[0].phases[0];
    expect(phase.weeks).toBe(1);
    expect(phase.description).toBe('Eigene Intonation hörbar machen');
    expect(phase.goal).toBe(
      'Erkennt abweichende Töne im Mitschnitt · Prüfung: Aufnahme gegen den Bordunton',
    );
    expect(bundle.programs[0].rationale).toContain('Die Intonation wird nicht gehört');
    expect(bundle.personalNote).toContain('Tonhöhen unterscheiden');
  });
});

describe('Tage verteilen', () => {
  it('legt drei Einheiten pro Woche auseinander, nicht hintereinander', () => {
    const tage = verteile(['a', 'b', 'c'], 3);
    expect(tage).toHaveLength(7);
    expect(tage.map((t) => t.routineId ?? '-')).toEqual(['a', '-', '-', 'b', '-', 'c', '-']);
  });

  it('füllt eine angebrochene Woche mit Pausentagen auf', () => {
    const tage = verteile(['a', 'b', 'c', 'd'], 3);
    // Zwei volle Wochen: der Rhythmus verschiebt sich über die Phase nicht.
    expect(tage).toHaveLength(14);
    expect(tage.filter((t) => t.routineId !== undefined)).toHaveLength(4);
  });

  it('kommt mit sieben Tagen pro Woche aus', () => {
    const tage = verteile(['a', 'b'], 7);
    expect(tage.slice(0, 2).map((t) => t.routineId)).toEqual(['a', 'b']);
  });
});
