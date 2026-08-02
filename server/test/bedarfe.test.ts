import { describe, expect, it } from 'vitest';
import { bedarfJePosition, dampfeEin, normalisiereZweck, positionsschluessel } from '../src/bedarfe';
import { bedarfstext, kosinus, tagAnteil } from '../src/embedding';
import type { Architektur, Einheit, Phase } from '../src/typen';
import { testEnvMitAi } from './hilfe';

/**
 * Ein Plan mit 3 Phasen × 6 Einheiten × 4 Übungen — 72 Positionen, aber nur
 * wenige verschiedene Bedarfe, wie es der Architekt-Prompt vorsieht.
 */
function grosserPlan(): Architektur {
  const zwecke = [
    { zweck: 'Ton gegen Bordun abgleichen', tags: ['geige', 'intonation'] },
    { zweck: 'Leersaiten stimmen', tags: ['geige', 'stimmen'] },
    { zweck: 'Eigene Aufnahme anhören', tags: ['geige', 'gehoer'] },
    { zweck: 'Bogen gleichmäßig führen', tags: ['geige', 'bogen'] },
  ];

  const phasen: Phase[] = [];
  for (let p = 0; p < 3; p++) {
    const einheiten: Einheit[] = [];
    for (let e = 0; e < 6; e++) {
      einheiten.push({
        nummer: e + 1,
        uebungen: zwecke.map((z, i) => ({
          zweck: z.zweck,
          tags: z.tags,
          // Dauer wandert pro Position, der Bedarf bleibt derselbe.
          dauer_min: 5 + i + p,
        })),
      });
    }
    phasen.push({
      titel: `Phase ${p + 1}`,
      ziel: 'Ziel',
      austrittskriterium: 'Kriterium',
      pruefung: 'Aufnahme gegen das Original',
      einheiten,
    });
  }
  return { programm_titel: 'Plan', programm_beschreibung: 'Text', phasen };
}

describe('normalisiereZweck', () => {
  it('macht aus Schreibvarianten denselben Schlüssel', () => {
    expect(normalisiereZweck('Ton gegen Bordun abgleichen.')).toBe(
      normalisiereZweck('ton  gegen bordun  abgleichen'),
    );
  });
});

describe('Bedarfe eindampfen (§7.1)', () => {
  it('macht aus 72 Positionen 4 Bedarfe', async () => {
    const env = testEnvMitAi();
    const { bedarfe, positionen, vektoren } = await dampfeEin(env, grosserPlan());

    expect(positionen).toBe(72);
    expect(bedarfe).toHaveLength(4);
    expect(vektoren).toHaveLength(4);
    // Jede Position hat genau einen Bedarf, keine ist verlorengegangen.
    expect(bedarfe.reduce((s, b) => s + b.positionen.length, 0)).toBe(72);
  });

  it('gibt jeder Position ihren Bedarf zurück', async () => {
    const env = testEnvMitAi();
    const plan = grosserPlan();
    const { bedarfe } = await dampfeEin(env, plan);
    const karte = bedarfJePosition(bedarfe);

    expect(karte.size).toBe(72);
    const bedarf = karte.get(positionsschluessel(2, 5, 3));
    expect(bedarf?.zweck).toBe('Bogen gleichmäßig führen');
  });

  it('behält dauer_min pro Position', async () => {
    const env = testEnvMitAi();
    const { bedarfe } = await dampfeEin(env, grosserPlan());
    const bogen = bedarfe.find((b) => b.zweck === 'Bogen gleichmäßig führen');

    const dauern = new Set(bogen?.positionen.map((p) => p.dauer_min));
    // Derselbe Bedarf, drei verschiedene Dauern — eine je Phase.
    expect([...dauern].sort((a, b) => a - b)).toEqual([8, 9, 10]);
  });

  it('legt zusammen, was sich nur in der Formulierung unterscheidet', async () => {
    const plan = grosserPlan();
    // Zwei Zwecke, die derselbe Bedarf sind — der Architekt hat die Regel
    // „wortgleich formulieren" gebrochen.
    plan.phasen[0].einheiten[0].uebungen[0].zweck = 'Den Ton am Bordun ausrichten';

    const env = testEnvMitAi({
      // Nah beieinander: derselbe Bedarf.
      'Den Ton am Bordun ausrichten': [1, 0.05, 0],
      'Ton gegen Bordun abgleichen': [1, 0, 0.05],
    });
    const { bedarfe } = await dampfeEin(env, plan);

    expect(bedarfe).toHaveLength(4);
    expect(bedarfe.reduce((s, b) => s + b.positionen.length, 0)).toBe(72);
  });

  it('lässt stehen, was inhaltlich verschieden ist', async () => {
    const env = testEnvMitAi();
    const { bedarfe } = await dampfeEin(env, grosserPlan());
    const zwecke = new Set(bedarfe.map((b) => b.zweck));
    expect(zwecke.size).toBe(4);
  });
});

describe('Bausteine der Ähnlichkeit', () => {
  it('kosinus ist unabhängig von der Länge des Vektors', () => {
    expect(kosinus([1, 0], [7, 0])).toBeCloseTo(1);
    expect(kosinus([1, 0], [0, 3])).toBeCloseTo(0);
  });

  it('tagAnteil misst die Überschneidung', () => {
    expect(tagAnteil(['geige', 'intonation'], ['geige', 'intonation'])).toBe(1);
    expect(tagAnteil(['geige'], ['krafttraining'])).toBe(0);
    expect(tagAnteil(['geige', 'intonation'], ['geige', 'bogen'])).toBeCloseTo(1 / 3);
  });

  it('bedarfstext ist von der Tag-Reihenfolge unabhängig', () => {
    expect(bedarfstext('Zweck', ['b', 'a'])).toBe(bedarfstext('Zweck', ['a', 'b']));
  });
});
