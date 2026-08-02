import { describe, expect, it } from 'vitest';
import { bausteintext } from '../src/embedding';
import { normalisiereTags, verarbeiteEntscheidung } from '../src/speichern';
import type { Kuratorentscheidung, NeueUebung } from '../src/typen';
import { fakeSpeicher } from './speicher';

const KONTEXT = { laufId: 'lauf-1', deviceId: 'geraet-1' };

const BESTAND: NeueUebung & { id: string } = {
  id: 'u-bestand',
  titel: 'Acht Takte aufnehmen und anhören',
  anleitung: 'Nimm die schwierigste Stelle auf und hör sie einmal ganz durch.',
  benefit: 'Du bemerkst Fehler, die du im Spielen nicht hörst',
  tags: ['geige', 'rueckkopplung', 'aufnahme'],
  equipment: ['aufnahmegeraet'],
  bild: null,
  animation: null,
};

function neu(ueberschreibe: Partial<NeueUebung> = {}): Kuratorentscheidung {
  return {
    aktion: 'create',
    kontext_hinweis: null,
    neue_uebung: {
      titel: 'Bogen im Spiegel führen',
      anleitung: 'Spiele lange Striche vor dem Spiegel und achte auf den Winkel.',
      benefit: 'Du siehst die Abweichung, statt sie zu erraten',
      tags: ['geige', 'bogen', 'haltung'],
      equipment: ['spiegel'],
      bild: null,
      animation: null,
      ...ueberschreibe,
    },
  };
}

describe('Speichern bei reuse', () => {
  it('zählt usage_count hoch und erzeugt nichts', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);

    const ergebnis = await verarbeiteEntscheidung(
      s.env,
      { aktion: 'reuse', uebung_id: 'u-bestand', kontext_hinweis: 'Beginne mit Takt 1' },
      KONTEXT,
    );

    expect(ergebnis.neu).toBe(false);
    expect(ergebnis.uebung_id).toBe('u-bestand');
    expect(ergebnis.kontext_hinweis).toBe('Beginne mit Takt 1');
    expect(s.uebungen.get('u-bestand')?.usage_count).toBe(1);
    expect(s.uebungen.size).toBe(1);
  });
});

describe('Dedupe (§9)', () => {
  it('speichert einen eigenständigen Baustein', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);

    const ergebnis = await verarbeiteEntscheidung(s.env, neu(), KONTEXT);

    expect(ergebnis.neu).toBe(true);
    expect(ergebnis.zurPruefung).toBe(false);
    expect(s.uebungen.size).toBe(2);
    expect(s.pruefliste).toHaveLength(0);
    // Zeile und Vektor gehören zusammen — ein Treffer ohne Zeile wäre im
    // Retrieval ein Kandidat, zu dem sich nichts nachladen lässt.
    expect(s.vektoren.has(ergebnis.uebung_id)).toBe(true);
    expect(s.uebungen.get(ergebnis.uebung_id)?.usage_count).toBe(1);
  });

  it('legt ein Fast-Duplikat in die Prüfliste statt in die Bibliothek', async () => {
    const fastGleich = neu({
      titel: 'Acht Takte aufnehmen und abhören',
      anleitung: 'Nimm die schwierigste Stelle auf und hör sie einmal ganz durch.',
      tags: ['geige', 'rueckkopplung', 'aufnahme'],
    });

    const s = fakeSpeicher({
      // Zwei Texte, die fast dasselbe sagen — 0,999 liegt über der Schwelle.
      [BESTAND.titel]: [1, 0, 0.02],
      'Acht Takte aufnehmen und abhören': [1, 0.02, 0],
    });
    await s.lege(BESTAND);

    const ergebnis = await verarbeiteEntscheidung(s.env, fastGleich, KONTEXT);

    expect(ergebnis.neu).toBe(false);
    expect(ergebnis.zurPruefung).toBe(true);
    // Für diesen Lauf gilt der Bestandsbaustein.
    expect(ergebnis.uebung_id).toBe('u-bestand');
    expect(s.uebungen.size).toBe(1);
    expect(s.pruefliste).toHaveLength(1);
    // Der tatsächliche Wert wird festgehalten, damit die geratene Schwelle
    // später an echten Daten justiert werden kann.
    expect(s.pruefliste[0].aehnlichkeit).toBeGreaterThanOrEqual(0.9);
    expect(s.pruefliste[0].bestand_id).toBe('u-bestand');
    expect(JSON.parse(s.pruefliste[0].kandidat).titel).toBe('Acht Takte aufnehmen und abhören');
  });

  it('kommt mit leerer Bibliothek zurecht', async () => {
    const s = fakeSpeicher();
    const ergebnis = await verarbeiteEntscheidung(s.env, neu(), KONTEXT);

    expect(ergebnis.neu).toBe(true);
    expect(ergebnis.aehnlichkeit).toBeNull();
  });
});

describe('Tag-Normalisierung (§9)', () => {
  it('macht aus violine das eingebürgerte geige', async () => {
    const s = fakeSpeicher({ geige: [1, 0, 0.05], violine: [1, 0.05, 0] });
    await s.lege(BESTAND);

    const { tags, neueTags } = await normalisiereTags(s.env, ['violine', 'aufnahme']);

    expect(tags).toContain('geige');
    expect(tags).not.toContain('violine');
    expect(neueTags).toEqual([]);
    expect(s.tagvokabular.has('violine')).toBe(false);
  });

  it('nimmt ein wirklich neues Tag auf', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);

    const { tags, neueTags } = await normalisiereTags(s.env, ['vibrato']);

    expect(tags).toEqual(['vibrato']);
    expect(neueTags).toEqual(['vibrato']);
    expect(s.tagvokabular.has('vibrato')).toBe(true);
    expect(s.tagVektoren.has('vibrato')).toBe(true);
  });

  it('zählt bekannte Tags hoch, statt sie zu doppeln', async () => {
    const s = fakeSpeicher();
    await s.lege(BESTAND);
    const vorher = s.tagvokabular.get('geige')?.count ?? 0;

    await normalisiereTags(s.env, ['geige', 'geige']);

    expect(s.tagvokabular.get('geige')?.count).toBe(vorher + 1);
    expect(s.tagvokabular.size).toBe(3);
  });
});

describe('Reihenfolge im Lauf (§9)', () => {
  it('erzeugt für zwei gleiche Bedarfe desselben Laufs nur einen Baustein', async () => {
    // Der Kurator entscheidet beim zweiten Bedarf erneut auf "create" — etwa
    // weil er den frischen Baustein anders formuliert. Das Dedupe fängt es ab,
    // aber nur weil sequenziell gespeichert wird.
    const s = fakeSpeicher({
      'Bogen im Spiegel führen': [1, 0, 0.02],
      'Bogenführung im Spiegel': [1, 0.02, 0],
    });

    const erst = await verarbeiteEntscheidung(s.env, neu(), KONTEXT);
    const zweit = await verarbeiteEntscheidung(
      s.env,
      neu({ titel: 'Bogenführung im Spiegel' }),
      KONTEXT,
    );

    expect(erst.neu).toBe(true);
    expect(zweit.neu).toBe(false);
    expect(zweit.uebung_id).toBe(erst.uebung_id);
    expect(s.uebungen.size).toBe(1);
    expect(s.pruefliste).toHaveLength(1);
  });
});

describe('bausteintext', () => {
  it('folgt §9: titel + anleitung + tags', () => {
    const text = bausteintext('Titel', 'Anleitung', ['b', 'a']);
    expect(text).toBe('Titel\nAnleitung\na, b');
  });
});
