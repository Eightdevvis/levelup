import {
  RUECKKOPPLUNG_QUELLEN,
  RUECKKOPPLUNG_STATUS,
  type Architektur,
  type Eingabe,
  type Einheit,
  type Kuratorentscheidung,
  type NeueUebung,
  type Phase,
  type Problemmodell,
  type Uebungsbedarf,
} from './typen';

/**
 * Prüfung jeder KI-Ausgabe, bevor sie irgendwohin weiterreist (Spec §4a).
 *
 * Der Angriff, um den es geht: Jemand schreibt ins Feld "Stand" einen Satz,
 * der wie eine Anweisung aussieht. Getrennte Rollen entschärfen das beim
 * ersten Aufruf — aber das Modell kann den Satz in `kernproblem`
 * weiterreichen, und von dort wandert er in den Architekten und in jeden
 * Kurator-Aufruf. Deshalb wird hier jede Ausgabe neu aufgebaut: nur bekannte
 * Felder, nur erlaubte Werte, Freitext auf plausible Länge gekürzt-oder-
 * abgelehnt. Was nicht passt, führt zum Neuversuch, nicht zur Weitergabe.
 *
 * Die Prüfung entfernt keinen untergeschobenen Satz aus einem Freitextfeld —
 * das ginge nur mit Raten. Sie sorgt dafür, dass er als Datum weiterreist:
 * begrenzt, in einem bekannten Feld, im nächsten Aufruf wieder getaggt.
 *
 * Von Hand geschrieben statt mit einer Schema-Bibliothek: es sind sechs
 * Schemata, und jede Abhängigkeit kostet den Worker Startzeit bei jedem
 * Kaltstart.
 */

export type Ergebnis<T> = { ok: true; wert: T } | { ok: false; fehler: string[] };

/** Obergrenzen für Freitext. Großzügig gewählt — sie sollen Ausreißer
 *  abfangen, nicht Formulierungen erziehen. */
const GRENZE = {
  kernproblem: 600,
  vermutete_ursache: 800,
  begruendung: 600,
  vorbild_wer: 120,
  vorbild_methode: 800,
  grundfaehigkeit: 200,
  rueckfrage: 300,
  programm_titel: 80,
  programm_beschreibung: 400,
  phasen_titel: 80,
  ziel: 400,
  austrittskriterium: 400,
  pruefung: 400,
  zweck: 200,
  titel: 80,
  anleitung: 800,
  benefit: 200,
  kontext_hinweis: 300,
  tag: 30,
  equipment: 60,
  url: 500,
} as const;

/** Anzahl-Obergrenzen. Ein Modell, das 400 Grundfähigkeiten aufzählt, hat die
 *  Aufgabe nicht verstanden — und der nächste Schritt zahlt die Token. */
const ANZAHL = {
  grundfaehigkeiten: 12,
  rueckfragen: 3, // "höchstens drei" (§5)
  phasen: 6,
  einheiten: 40,
  uebungen: 10,
  tags: 10,
  equipment: 12,
} as const;

// --- Bausteine der Prüfung -------------------------------------------------

class Sammler {
  readonly fehler: string[] = [];

  melde(pfad: string, was: string): void {
    this.fehler.push(`${pfad}: ${was}`);
  }
}

function objekt(roh: unknown, pfad: string, s: Sammler): Record<string, unknown> {
  if (roh === null || typeof roh !== 'object' || Array.isArray(roh)) {
    s.melde(pfad, 'muss ein Objekt sein');
    return {};
  }
  return roh as Record<string, unknown>;
}

function text(
  o: Record<string, unknown>,
  feld: string,
  max: number,
  pfad: string,
  s: Sammler,
): string {
  const wert = o[feld];
  if (typeof wert !== 'string') {
    s.melde(`${pfad}.${feld}`, 'fehlt oder ist kein Text');
    return '';
  }
  const sauber = wert.trim();
  if (sauber.length === 0) {
    s.melde(`${pfad}.${feld}`, 'ist leer');
    return '';
  }
  if (sauber.length > max) {
    s.melde(`${pfad}.${feld}`, `ist länger als ${max} Zeichen (${sauber.length})`);
    return '';
  }
  return sauber;
}

/** Wie [text], nur darf das Feld fehlen oder `null` sein. */
function optionalerText(
  o: Record<string, unknown>,
  feld: string,
  max: number,
  pfad: string,
  s: Sammler,
): string | null {
  const wert = o[feld];
  if (wert === undefined || wert === null || wert === '') return null;
  if (typeof wert !== 'string') {
    s.melde(`${pfad}.${feld}`, 'ist kein Text');
    return null;
  }
  const sauber = wert.trim();
  if (sauber.length === 0) return null;
  if (sauber.length > max) {
    s.melde(`${pfad}.${feld}`, `ist länger als ${max} Zeichen (${sauber.length})`);
    return null;
  }
  return sauber;
}

function auswahl<T extends string>(
  o: Record<string, unknown>,
  feld: string,
  erlaubt: readonly T[],
  pfad: string,
  s: Sammler,
): T {
  const wert = o[feld];
  if (typeof wert !== 'string' || !erlaubt.includes(wert as T)) {
    s.melde(`${pfad}.${feld}`, `muss einer von [${erlaubt.join(', ')}] sein`);
    return erlaubt[0];
  }
  return wert as T;
}

function zahl(
  o: Record<string, unknown>,
  feld: string,
  min: number,
  max: number,
  pfad: string,
  s: Sammler,
): number {
  const wert = o[feld];
  if (typeof wert !== 'number' || !Number.isFinite(wert)) {
    s.melde(`${pfad}.${feld}`, 'fehlt oder ist keine Zahl');
    return min;
  }
  const gerundet = Math.round(wert);
  if (gerundet < min || gerundet > max) {
    s.melde(`${pfad}.${feld}`, `muss zwischen ${min} und ${max} liegen (${gerundet})`);
    return min;
  }
  return gerundet;
}

function textliste(
  o: Record<string, unknown>,
  feld: string,
  grenzen: { max: number; minAnzahl: number; maxAnzahl: number },
  pfad: string,
  s: Sammler,
): string[] {
  const wert = o[feld];
  if (!Array.isArray(wert)) {
    s.melde(`${pfad}.${feld}`, 'fehlt oder ist keine Liste');
    return [];
  }
  if (wert.length > grenzen.maxAnzahl) {
    s.melde(`${pfad}.${feld}`, `hat mehr als ${grenzen.maxAnzahl} Einträge (${wert.length})`);
    return [];
  }
  const raus: string[] = [];
  for (const [i, eintrag] of wert.entries()) {
    if (typeof eintrag !== 'string') {
      s.melde(`${pfad}.${feld}[${i}]`, 'ist kein Text');
      continue;
    }
    const sauber = eintrag.trim();
    if (sauber.length === 0) continue;
    if (sauber.length > grenzen.max) {
      s.melde(`${pfad}.${feld}[${i}]`, `ist länger als ${grenzen.max} Zeichen`);
      continue;
    }
    raus.push(sauber);
  }
  if (raus.length < grenzen.minAnzahl) {
    s.melde(`${pfad}.${feld}`, `braucht mindestens ${grenzen.minAnzahl} Einträge`);
  }
  return raus;
}

/**
 * Tags in ihre kanonische Form. Kleinschreibung und ein einziges Leerzeichen
 * sind keine Geschmacksfrage: Tags sind Suchschlüssel, und "Geige" neben
 * "geige" wäre bereits die Zersplitterung, die §9 verhindern soll.
 */
export function normalisiereTag(roh: string): string {
  return roh.trim().toLowerCase().replace(/\s+/g, ' ').replace(/[.,;:!?]+$/u, '');
}

function tagliste(
  o: Record<string, unknown>,
  feld: string,
  minAnzahl: number,
  pfad: string,
  s: Sammler,
): string[] {
  const roh = textliste(
    o,
    feld,
    { max: GRENZE.tag, minAnzahl, maxAnzahl: ANZAHL.tags },
    pfad,
    s,
  );
  const gesehen = new Set<string>();
  const raus: string[] = [];
  for (const tag of roh.map(normalisiereTag)) {
    if (tag.length === 0 || gesehen.has(tag)) continue;
    gesehen.add(tag);
    raus.push(tag);
  }
  return raus;
}

function ergebnis<T>(wert: T, s: Sammler): Ergebnis<T> {
  return s.fehler.length === 0 ? { ok: true, wert } : { ok: false, fehler: s.fehler };
}

// --- Nutzereingabe (Spec §3) -----------------------------------------------

/**
 * Die vier Felder von der App. Kein KI-Ergebnis, aber genauso wenig
 * vertrauenswürdig: sie kommen von einem Gerät, das der Betreiber nicht
 * kontrolliert, und der Betreiber zahlt die Eingabe-Token.
 */
export function pruefeEingabe(roh: unknown, maxZeichen: number): Ergebnis<Eingabe> {
  const s = new Sammler();
  const o = objekt(roh, 'eingabe', s);
  const eingabe: Eingabe = {
    vorhaben: text(o, 'vorhaben', maxZeichen, 'eingabe', s),
    stand: optionalerText(o, 'stand', maxZeichen, 'eingabe', s) ?? '',
    minuten_pro_tag: zahl(o, 'minuten_pro_tag', 5, 600, 'eingabe', s),
    tage_pro_woche: zahl(o, 'tage_pro_woche', 1, 7, 'eingabe', s),
    equipment: optionalerText(o, 'equipment', maxZeichen, 'eingabe', s) ?? '',
  };
  return ergebnis(eingabe, s);
}

// --- [1] Problemmodell (Spec §5) -------------------------------------------

export function pruefeProblemmodell(roh: unknown): Ergebnis<Problemmodell> {
  const s = new Sammler();
  const o = objekt(roh, 'problemmodell', s);
  const rk = objekt(o.rueckkopplung, 'problemmodell.rueckkopplung', s);
  const vorbild = objekt(o.vorbild, 'problemmodell.vorbild', s);

  const modell: Problemmodell = {
    kernproblem: text(o, 'kernproblem', GRENZE.kernproblem, 'problemmodell', s),
    vermutete_ursache: text(
      o,
      'vermutete_ursache',
      GRENZE.vermutete_ursache,
      'problemmodell',
      s,
    ),
    rueckkopplung: {
      quelle: auswahl(rk, 'quelle', RUECKKOPPLUNG_QUELLEN, 'problemmodell.rueckkopplung', s),
      status: auswahl(rk, 'status', RUECKKOPPLUNG_STATUS, 'problemmodell.rueckkopplung', s),
      begruendung: text(rk, 'begruendung', GRENZE.begruendung, 'problemmodell.rueckkopplung', s),
    },
    vorbild: {
      wer: text(vorbild, 'wer', GRENZE.vorbild_wer, 'problemmodell.vorbild', s),
      methode: text(vorbild, 'methode', GRENZE.vorbild_methode, 'problemmodell.vorbild', s),
    },
    grundfaehigkeiten: textliste(
      o,
      'grundfaehigkeiten',
      { max: GRENZE.grundfaehigkeit, minAnzahl: 1, maxAnzahl: ANZAHL.grundfaehigkeiten },
      'problemmodell',
      s,
    ),
    // Leer ist der Normalfall und kein Fehler: das Modell soll nur fragen,
    // wenn die Antwort den Plan verändern würde.
    rueckfragen: Array.isArray(o.rueckfragen)
      ? textliste(
          o,
          'rueckfragen',
          { max: GRENZE.rueckfrage, minAnzahl: 0, maxAnzahl: ANZAHL.rueckfragen },
          'problemmodell',
          s,
        )
      : [],
  };
  return ergebnis(modell, s);
}

// --- [2] Architektur (Spec §6) ---------------------------------------------

function pruefeUebungsbedarf(roh: unknown, pfad: string, s: Sammler): Uebungsbedarf {
  const o = objekt(roh, pfad, s);
  return {
    zweck: text(o, 'zweck', GRENZE.zweck, pfad, s),
    tags: tagliste(o, 'tags', 1, pfad, s),
    dauer_min: zahl(o, 'dauer_min', 1, 240, pfad, s),
  };
}

function pruefeEinheit(roh: unknown, nummer: number, pfad: string, s: Sammler): Einheit {
  const o = objekt(roh, pfad, s);
  const uebungen = Array.isArray(o.uebungen) ? o.uebungen : [];
  if (!Array.isArray(o.uebungen)) s.melde(`${pfad}.uebungen`, 'fehlt oder ist keine Liste');
  if (uebungen.length > ANZAHL.uebungen) {
    s.melde(`${pfad}.uebungen`, `hat mehr als ${ANZAHL.uebungen} Einträge`);
    return { nummer, uebungen: [] };
  }
  return {
    // Die Nummer aus der Ausgabe ist Beiwerk; verlassen wird sich auf die
    // Reihenfolge, sonst hängt der Aufbau an einem Zählfehler des Modells.
    nummer,
    uebungen: uebungen.map((u, i) => pruefeUebungsbedarf(u, `${pfad}.uebungen[${i}]`, s)),
  };
}

function pruefePhase(roh: unknown, pfad: string, s: Sammler): Phase {
  const o = objekt(roh, pfad, s);
  const einheiten = Array.isArray(o.einheiten) ? o.einheiten : [];
  if (!Array.isArray(o.einheiten)) s.melde(`${pfad}.einheiten`, 'fehlt oder ist keine Liste');
  if (einheiten.length > ANZAHL.einheiten) {
    s.melde(`${pfad}.einheiten`, `hat mehr als ${ANZAHL.einheiten} Einträge`);
    return {
      titel: '',
      ziel: '',
      austrittskriterium: '',
      pruefung: '',
      einheiten: [],
    };
  }
  return {
    titel: text(o, 'titel', GRENZE.phasen_titel, pfad, s),
    ziel: text(o, 'ziel', GRENZE.ziel, pfad, s),
    austrittskriterium: text(o, 'austrittskriterium', GRENZE.austrittskriterium, pfad, s),
    pruefung: text(o, 'pruefung', GRENZE.pruefung, pfad, s),
    einheiten: einheiten.map((e, i) => pruefeEinheit(e, i + 1, `${pfad}.einheiten[${i}]`, s)),
  };
}

export function pruefeArchitektur(roh: unknown): Ergebnis<Architektur> {
  const s = new Sammler();
  const o = objekt(roh, 'architektur', s);
  const phasen = Array.isArray(o.phasen) ? o.phasen : [];
  if (!Array.isArray(o.phasen)) s.melde('architektur.phasen', 'fehlt oder ist keine Liste');
  if (phasen.length > ANZAHL.phasen) {
    s.melde('architektur.phasen', `hat mehr als ${ANZAHL.phasen} Phasen (${phasen.length})`);
  }
  if (phasen.length === 0) s.melde('architektur.phasen', 'ist leer');

  const architektur: Architektur = {
    programm_titel: text(o, 'programm_titel', GRENZE.programm_titel, 'architektur', s),
    programm_beschreibung: text(
      o,
      'programm_beschreibung',
      GRENZE.programm_beschreibung,
      'architektur',
      s,
    ),
    phasen:
      phasen.length > ANZAHL.phasen
        ? []
        : phasen.map((p, i) => pruefePhase(p, `architektur.phasen[${i}]`, s)),
  };
  return ergebnis(architektur, s);
}

/**
 * Regeln aus dem Architekten-Prompt, deren Bruch den Rest wertlos macht.
 *
 * Getrennt von der Schemaprüfung, weil es keine Formfehler sind: die Ausgabe
 * ist wohlgeformt und trotzdem unbrauchbar. Ein Austrittskriterium ohne
 * Prüfung ist genau der Fehler, den §11 als tragende Regel benennt, und eine
 * Einheit, die das Zeitbudget sprengt, wird nie durchgeführt.
 */
export function pruefeArchitekturRegeln(
  architektur: Architektur,
  minutenProTag: number,
): string[] {
  const fehler: string[] = [];
  // 20 % Toleranz: das Modell rundet, und ein 21-Minuten-Block bei 20 Minuten
  // Budget ist kein Regelbruch, sondern Rundung.
  const budget = Math.round(minutenProTag * 1.2);

  architektur.phasen.forEach((phase, pi) => {
    const pfad = `phasen[${pi}] "${phase.titel}"`;
    if (phase.einheiten.length === 0) {
      fehler.push(`${pfad}: hat keine Einheiten`);
    }
    phase.einheiten.forEach((einheit, ei) => {
      const epfad = `${pfad}.einheiten[${ei}]`;
      if (einheit.uebungen.length < 3 || einheit.uebungen.length > 5) {
        fehler.push(
          `${epfad}: braucht 3 bis 5 Übungen, hat ${einheit.uebungen.length}`,
        );
      }
      const summe = einheit.uebungen.reduce((a, u) => a + u.dauer_min, 0);
      if (summe > budget) {
        fehler.push(
          `${epfad}: dauert ${summe} Min., verfügbar sind ${minutenProTag} Min. pro Tag`,
        );
      }
    });
  });
  return fehler;
}

// --- [4] Kuratorentscheidung (Spec §8) -------------------------------------

function pruefeNeueUebung(roh: unknown, pfad: string, s: Sammler): NeueUebung {
  const o = objekt(roh, pfad, s);
  return {
    titel: text(o, 'titel', GRENZE.titel, pfad, s),
    anleitung: text(o, 'anleitung', GRENZE.anleitung, pfad, s),
    benefit: text(o, 'benefit', GRENZE.benefit, pfad, s),
    tags: tagliste(o, 'tags', 2, pfad, s),
    equipment: Array.isArray(o.equipment)
      ? textliste(
          o,
          'equipment',
          { max: GRENZE.equipment, minAnzahl: 0, maxAnzahl: ANZAHL.equipment },
          pfad,
          s,
        )
      : [],
    bild: optionalerText(o, 'bild', GRENZE.url, pfad, s),
    animation: optionalerText(o, 'animation', GRENZE.url, pfad, s),
  };
}

/**
 * Ein einzelner Baustein für sich — für den Grundstock, der von Hand
 * geschrieben ist und trotzdem durch dieselbe Prüfung muss wie alles, was die
 * KI liefert. Ein Tippfehler im Kaltstart wäre der Maßstab für alles Spätere.
 */
export function pruefeBaustein(roh: unknown): Ergebnis<NeueUebung> {
  const s = new Sammler();
  return ergebnis(pruefeNeueUebung(roh, 'baustein', s), s);
}

/**
 * `kandidatenIds` ist der Halluzinationsschutz: Bei `reuse` muss die ID aus
 * der Liste stammen, die dem Modell im selben Aufruf vorgelegt wurde. Eine
 * erfundene ID würde sonst zu einer Übungsreferenz ins Leere — in der App
 * eine Platzhalter-Übung mitten im Plan.
 */
export function pruefeKuratorentscheidung(
  roh: unknown,
  kandidatenIds: readonly string[],
): Ergebnis<Kuratorentscheidung> {
  const s = new Sammler();
  const o = objekt(roh, 'entscheidung', s);
  const aktion = auswahl(o, 'aktion', ['reuse', 'create'] as const, 'entscheidung', s);
  const hinweis = optionalerText(o, 'kontext_hinweis', GRENZE.kontext_hinweis, 'entscheidung', s);

  if (aktion === 'reuse') {
    const id = typeof o.uebung_id === 'string' ? o.uebung_id.trim() : '';
    if (!kandidatenIds.includes(id)) {
      s.melde(
        'entscheidung.uebung_id',
        `"${id}" steht nicht in der Kandidatenliste — erlaubt sind nur die vorgelegten IDs`,
      );
    }
    return ergebnis({ aktion, uebung_id: id, kontext_hinweis: hinweis }, s);
  }

  return ergebnis(
    { aktion, kontext_hinweis: hinweis, neue_uebung: pruefeNeueUebung(o.neue_uebung, 'entscheidung.neue_uebung', s) },
    s,
  );
}
