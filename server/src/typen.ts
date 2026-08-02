/**
 * Die Objekte der Spezifikation, eins zu eins.
 *
 * Deutsche Feldnamen, weil die Spec sie so nennt und weil sie in dieser Form
 * durch die Prompts, die Datenbank und die Prüfung wandern. Übersetzt wird
 * genau einmal: in `bundle.ts`, beim Zusammenbau für die App.
 */

// --- Eingabe (Spec §3) -----------------------------------------------------

export interface Eingabe {
  vorhaben: string;
  stand: string;
  minuten_pro_tag: number;
  tage_pro_woche: number;
  equipment: string;
}

/** Eine beantwortete Rückfrage. Übersprungene reisen mit, damit das Modell
 *  im zweiten Durchlauf sieht, dass es keine Antwort gibt — statt zu raten. */
export interface Rueckfrageantwort {
  frage: string;
  antwort: string | null;
}

// --- [1] Diagnose (Spec §5) ------------------------------------------------

export const RUECKKOPPLUNG_QUELLEN = [
  'vorlage',
  'richtige_antwort',
  'ergebnis',
  'fremde_rueckmeldung',
] as const;
export type RueckkopplungQuelle = (typeof RUECKKOPPLUNG_QUELLEN)[number];

export const RUECKKOPPLUNG_STATUS = ['vorhanden', 'fehlt', 'zu_spaet'] as const;
export type RueckkopplungStatus = (typeof RUECKKOPPLUNG_STATUS)[number];

export interface Problemmodell {
  kernproblem: string;
  vermutete_ursache: string;
  rueckkopplung: {
    quelle: RueckkopplungQuelle;
    status: RueckkopplungStatus;
    begruendung: string;
  };
  vorbild: { wer: string; methode: string };
  grundfaehigkeiten: string[];
  rueckfragen: string[];
}

// --- [2] Architekt (Spec §6) -----------------------------------------------

/** Was eine Übung an dieser Stelle leisten muss. Noch kein Baustein. */
export interface Uebungsbedarf {
  zweck: string;
  tags: string[];
  dauer_min: number;
}

export interface Einheit {
  nummer: number;
  uebungen: Uebungsbedarf[];
}

export interface Phase {
  titel: string;
  ziel: string;
  austrittskriterium: string;
  /** Woran der Nutzer die Fähigkeit selbst feststellt — an einem Signal
   *  außerhalb seines Urteils. Ohne das ist das Kriterium wertlos (§11). */
  pruefung: string;
  einheiten: Einheit[];
}

export interface Architektur {
  /**
   * Titel und Beschreibung kommen in der Spec in keinem Prompt vor, die App
   * zeigt aber beides an. Ohne diese zwei Felder hieße jeder Plan "Programm".
   */
  programm_titel: string;
  programm_beschreibung: string;
  phasen: Phase[];
}

// --- [3] Bedarfe (Spec §7.1) -----------------------------------------------

/** Wo im Plan eine Übung gebraucht wird. `dauer_min` bleibt hier und nicht
 *  am Bedarf: dieselbe Übung läuft an zwei Stellen unterschiedlich lang. */
export interface Position {
  phase: number;
  einheit: number;
  index: number;
  dauer_min: number;
}

/** Ein eindeutiger Bedarf mit allen Positionen, die ihn teilen. Der Kurator
 *  läuft einmal je Bedarf, nicht einmal je Position. */
export interface Bedarf {
  id: string;
  zweck: string;
  tags: string[];
  positionen: Position[];
}

// --- Bibliothek (Spec §2.1) ------------------------------------------------

/** Der Baustein, wie ihn die KI schreibt — ohne die vom Code verwalteten Felder. */
export interface NeueUebung {
  titel: string;
  anleitung: string;
  benefit: string;
  tags: string[];
  equipment: string[];
  bild: string | null;
  animation: string | null;
}

export interface Uebung extends NeueUebung {
  id: string;
}

/** Wie der Baustein in der Datenbank liegt. */
export interface UebungDatensatz extends Uebung {
  created_at: number;
  usage_count: number;
  source_program_id: string | null;
  source_device_id: string | null;
  status: 'aktiv' | 'zurueckgestellt';
}

/** Was der Kurator als Auswahl vorgelegt bekommt: alles außer den Medien —
 *  eine URL hilft bei der Entscheidung nicht und kostet nur Token (§7.2). */
export type Kandidat = Omit<Uebung, 'bild' | 'animation'>;

/** Ein Programm speichert Referenzen, keine Kopien (§2.2). */
export interface Uebungsreferenz {
  uebung_id: string;
  dauer_min: number;
  kontext_hinweis: string | null;
}

// --- [4] Kurator (Spec §8) -------------------------------------------------

export type Kuratorentscheidung =
  | { aktion: 'reuse'; uebung_id: string; kontext_hinweis: string | null }
  | { aktion: 'create'; kontext_hinweis: string | null; neue_uebung: NeueUebung };

// --- Lauf ------------------------------------------------------------------

export const LAUF_STATUS = [
  'diagnose',
  'rueckfragen',
  'plan',
  'fertig',
  'fehlgeschlagen',
] as const;
export type LaufStatus = (typeof LAUF_STATUS)[number];

export interface Lauf {
  id: string;
  device_id: string;
  created_at: number;
  status: LaufStatus;
  eingabe: Eingabe;
  rueckfragen: string[];
  problemmodell: Problemmodell | null;
  architektur: Architektur | null;
  generation_id: string | null;
}

/** Die vier Zahlen aus §11, je Lauf. */
export interface Kennzahlen {
  bedarfe: number;
  reuse: number;
  neu: number;
  neue_tags: number;
  pruefliste: number;
  uebungspositionen: number;
}
