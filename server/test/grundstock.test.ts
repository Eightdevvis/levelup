import { describe, expect, it } from 'vitest';
import geige from '../grundstock/geige.json';
import krafttraining from '../grundstock/krafttraining.json';
import { normalisiereTag, pruefeBaustein } from '../src/pruefen';

/**
 * Der Grundstock legt das Niveau fest, an dem sich jede spätere Generierung
 * orientiert — Kandidaten aus dem Bestand gehen als Beispiele mit. Ein
 * schiefer Anfang bleibt im System (§10). Deshalb prüft ihn dasselbe Schema
 * wie jede KI-Ausgabe.
 */

const DATEIEN = [
  { name: 'geige', inhalt: geige },
  { name: 'krafttraining', inhalt: krafttraining },
];

describe.each(DATEIEN)('Grundstock $name', ({ inhalt }) => {
  it('hat 10 bis 15 Bausteine (§10)', () => {
    expect(inhalt.bausteine.length).toBeGreaterThanOrEqual(10);
    expect(inhalt.bausteine.length).toBeLessThanOrEqual(15);
  });

  it('hält jeder Baustein der Schemaprüfung stand', () => {
    for (const baustein of inhalt.bausteine) {
      const geprueft = pruefeBaustein(baustein);
      expect(geprueft.ok ? [] : geprueft.fehler).toEqual([]);
    }
  });

  it('trägt jeder Baustein das Tätigkeits-Tag', () => {
    for (const baustein of inhalt.bausteine) {
      expect(baustein.tags).toContain(inhalt.taetigkeit);
    }
  });

  it('hat normalisierte Tags — der erste Bestand ist der Maßstab', () => {
    for (const baustein of inhalt.bausteine) {
      for (const tag of baustein.tags) {
        expect(tag).toBe(normalisiereTag(tag));
      }
    }
  });

  it('vergibt jede ID nur einmal', () => {
    const ids = inhalt.bausteine.map((b) => b.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('hat bei der Hälfte den Schwerpunkt Rückkopplung (§10)', () => {
    const mit = inhalt.bausteine.filter((b) => b.tags.includes('rueckkopplung'));
    expect(mit.length).toBeGreaterThanOrEqual(inhalt.bausteine.length / 2);
  });
});

describe('Die fünf Beispiele aus §10', () => {
  const erwartet = [
    {
      titel: 'Acht Takte aufnehmen und anhören',
      anleitung:
        'Nimm die schwierigste Stelle deines aktuellen Stücks auf. Hör die Aufnahme einmal ganz durch, ohne Instrument in der Hand. Notiere die Stelle, die dich als Erstes stört.',
      benefit: 'Du bemerkst Fehler, die du im Spielen nicht hörst',
    },
    {
      titel: 'Aufnahme gegen Original stellen',
      anleitung:
        'Spiele deine Aufnahme und eine Originalaufnahme derselben Stelle direkt hintereinander ab. Benenne den Unterschied in einem Satz.',
      benefit: 'Du erkennst nicht nur, dass etwas abweicht, sondern wo',
    },
    {
      titel: 'Vier Takte singen, bevor du sie spielst',
      anleitung:
        'Sing die nächsten vier Takte, ohne Instrument. Erst wenn du sie singen kannst, nimmst du die Geige.',
      benefit: 'Du weißt vor dem ersten Versuch, was herauskommen soll',
    },
    {
      titel: 'Note singen, dann anspielen',
      anleitung:
        'Sing die Note, die du liest. Spiel sie danach an. Stimmte sie, weiter; stimmte sie nicht, dieselbe Zeile noch einmal.',
      benefit: 'Falsches setzt sich nicht fest, weil du es sofort bemerkst',
    },
    {
      titel: 'Auf zwei Takte verkleinern',
      anleitung:
        'Nimm zwei Takte statt acht. Wiederhole, bis dieselbe Stelle dreimal hintereinander gleich klingt.',
      benefit: 'Du siehst, woran es liegt, statt nur dass es nicht klappt',
    },
  ];

  it('stehen wortgleich in geige.json', () => {
    erwartet.forEach((soll, i) => {
      const ist = geige.bausteine[i];
      expect({ titel: ist.titel, anleitung: ist.anleitung, benefit: ist.benefit }).toEqual(soll);
    });
  });
});

describe('Tätigkeiten trennen sich', () => {
  it('teilen kein einziges Tag außer den allgemeinen', () => {
    const geigeTags = new Set(geige.bausteine.flatMap((b) => b.tags));
    const kraftTags = new Set(krafttraining.bausteine.flatMap((b) => b.tags));
    const gemeinsam = [...geigeTags].filter((t) => kraftTags.has(t));

    // Gemeinsam sind nur Tags, die keine Tätigkeit benennen — sonst würde eine
    // Suche nach Geige Kandidaten aus dem Krafttraining hochziehen.
    expect(gemeinsam).not.toContain('geige');
    expect(gemeinsam).not.toContain('krafttraining');
    expect(gemeinsam).toContain('rueckkopplung');
  });
});
