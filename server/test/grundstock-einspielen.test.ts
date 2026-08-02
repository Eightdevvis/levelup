import { describe, expect, it } from 'vitest';
import geige from '../grundstock/geige.json';
import { pruefeGrundstock, spieleEin, type Grundstockdatei } from '../src/grundstock';
import { fakeSpeicher } from './speicher';

/**
 * Der Kaltstart muss zweimal laufen dürfen: das Skript wird gegen die
 * laufende API ausgeführt, und wer nicht sicher weiß, ob es durchlief, führt
 * es noch einmal aus.
 */
describe('Grundstock einspielen (§10)', () => {
  it('nimmt die echte Datei an', () => {
    const geprueft = pruefeGrundstock(geige);
    expect(Array.isArray(geprueft)).toBe(false);
    expect((geprueft as Grundstockdatei).bausteine).toHaveLength(12);
  });

  it('legt Bausteine, Vektoren und Vokabular an', async () => {
    const s = fakeSpeicher();
    const bericht = await spieleEin(s.env, pruefeGrundstock(geige) as Grundstockdatei);

    expect(bericht.angelegt).toHaveLength(12);
    expect(s.uebungen.size).toBe(12);
    expect(s.vektoren.size).toBe(12);
    // Das Tätigkeits-Tag ist als solches vermerkt — daraus wird später
    // Exercise.domain.
    expect(s.tagvokabular.get('geige')?.istTaetigkeit).toBe(true);
    expect(s.tagvokabular.get('rueckkopplung')?.istTaetigkeit).toBe(false);
    // Ungebraucht bis ein Plan sie einsetzt.
    expect([...s.uebungen.values()].every((z) => z.usage_count === 0)).toBe(true);
  });

  it('doppelt beim zweiten Lauf nichts', async () => {
    const s = fakeSpeicher();
    const datei = pruefeGrundstock(geige) as Grundstockdatei;
    await spieleEin(s.env, datei);
    const zweiter = await spieleEin(s.env, datei);

    expect(zweiter.angelegt).toEqual([]);
    expect(zweiter.uebersprungen).toHaveLength(12);
    expect(s.uebungen.size).toBe(12);
  });

  it('weist eine Datei ohne Kennungen zurück', () => {
    const fehler = pruefeGrundstock({ taetigkeit: 'geige', bausteine: [{ titel: 'Ohne id' }] });
    expect(Array.isArray(fehler)).toBe(true);
    expect((fehler as string[])[0]).toContain('id: fehlt');
  });
});
