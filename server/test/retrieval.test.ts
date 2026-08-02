import { describe, expect, it } from 'vitest';
import { MAX_KANDIDATEN, reihe, sucheKandidaten, TAG_GEWICHT } from '../src/retrieval';
import type { Bedarf, Kandidat } from '../src/typen';
import { fakeBibliothek } from './hilfe';

/**
 * Der Fall, den §7.2 ausdrücklich nennt: „langsam ausführen und dabei genau
 * hinhören" passt formulierungsseitig auf Geige wie auf Kniebeugen. Der
 * Vektorindex bewertet den fachfremden Baustein sogar minimal höher — erst die
 * Tag-Gewichtung dreht die Reihenfolge.
 */
const GEIGE: Kandidat = {
  id: 'u-geige',
  titel: 'Langsamer Tonbogen',
  anleitung: 'Spiele jeden Ton langsam und hör genau hin.',
  benefit: 'Intonation',
  tags: ['geige', 'intonation'],
  equipment: ['geige'],
};

const KRAFT: Kandidat = {
  id: 'u-kraft',
  titel: 'Langsame Wiederholung',
  anleitung: 'Führe die Bewegung langsam aus und hör genau hin.',
  benefit: 'Technik',
  tags: ['krafttraining', 'technik'],
  equipment: ['langhantel'],
};

const BEDARF: Bedarf = {
  id: 'b1',
  zweck: 'Langsam ausführen und dabei genau hinhören',
  tags: ['geige', 'intonation'],
  positionen: [{ phase: 0, einheit: 0, index: 0, dauer_min: 10 }],
};

describe('Reihung (§7.2)', () => {
  it('schiebt den fachfremden Kandidaten trotz höherer Ähnlichkeit nach hinten', () => {
    const gereiht = reihe(
      [
        { id: 'u-kraft', score: 0.84 },
        { id: 'u-geige', score: 0.81 },
      ],
      [GEIGE, KRAFT],
      BEDARF.tags,
    );

    expect(gereiht.map((k) => k.id)).toEqual(['u-geige', 'u-kraft']);
  });

  it('lässt die Reihenfolge, wenn der Abstand zu groß ist', () => {
    // Ohne gemeinsame Tags kann die Gewichtung höchstens um TAG_GEWICHT
    // anheben; ein Vorsprung darüber hinaus bleibt bestehen.
    const gereiht = reihe(
      [
        { id: 'u-kraft', score: 0.9 },
        { id: 'u-geige', score: 0.5 },
      ],
      [GEIGE, KRAFT],
      BEDARF.tags,
    );

    expect(gereiht[0].id).toBe('u-kraft');
    expect(0.5 * (1 + TAG_GEWICHT)).toBeLessThan(0.9);
  });

  it('übergeht Treffer, zu denen keine Zeile mehr existiert', () => {
    const gereiht = reihe(
      [
        { id: 'weg', score: 0.99 },
        { id: 'u-geige', score: 0.4 },
      ],
      [GEIGE],
      BEDARF.tags,
    );
    expect(gereiht.map((k) => k.id)).toEqual(['u-geige']);
  });

  it('legt dem Kurator höchstens zehn vor', () => {
    const viele = Array.from({ length: 20 }, (_, i) => ({ ...GEIGE, id: `u${i}` }));
    const treffer = viele.map((k, i) => ({ id: k.id, score: 1 - i / 100 }));
    expect(reihe(treffer, viele, BEDARF.tags)).toHaveLength(MAX_KANDIDATEN);
  });
});

describe('Suche', () => {
  it('fragt nur aktive Bausteine ab und meldet die Trefferzahl', async () => {
    const { env, vectorizeAufrufe } = fakeBibliothek({
      kandidaten: [GEIGE, KRAFT],
      treffer: [
        { id: 'u-kraft', score: 0.84 },
        { id: 'u-geige', score: 0.81 },
      ],
    });

    const gemeldet: number[] = [];
    const gereiht = await sucheKandidaten(env, BEDARF, [1, 0, 0], (e) => {
      if (e.type === 'search') gemeldet.push(e.hits);
    });

    expect(gereiht.map((k) => k.id)).toEqual(['u-geige', 'u-kraft']);
    expect(vectorizeAufrufe[0].optionen.filter).toEqual({ status: 'aktiv' });
    expect(gemeldet).toEqual([2]);
  });

  it('kommt mit leerer Bibliothek zurecht', async () => {
    const { env } = fakeBibliothek({ kandidaten: [], treffer: [] });
    expect(await sucheKandidaten(env, BEDARF, [1, 0, 0])).toEqual([]);
  });
});
