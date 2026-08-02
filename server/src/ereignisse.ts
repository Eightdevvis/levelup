/**
 * Das Protokoll zur App.
 *
 * Bewusst klein und eigen: die App muss Anthropics Ereignisformat nicht
 * kennen, und was hier nicht vorkommt, kann kein Gerät zu sehen bekommen.
 */
export type Ereignis =
  /** Der letzte Satz des Gedankengangs. */
  | { type: 'thinking'; text: string }
  /** Bisherige Länge der Antwort — genug für einen Fortschrittsbalken, ohne
   *  halbfertiges JSON zu verschicken. */
  | { type: 'writing'; chars: number }
  /** Welcher Pipeline-Schritt gerade läuft. `fertig`/`gesamt` beim Kurator,
   *  der pro Bedarf einmal läuft und deshalb am längsten dauert. */
  | { type: 'schritt'; name: Schrittname; fertig?: number; gesamt?: number }
  /** Ein Blick in die Bibliothek. Sichtbar zu machen ist Absicht: der Nutzer
   *  soll sehen, dass nicht alles neu erfunden wird. */
  | { type: 'search'; tool: string; terms: string[]; hits: number }
  /** Eine KI-Ausgabe hielt der Prüfung nicht stand und wird nachgebessert. */
  | { type: 'repair'; problems: number };

export const SCHRITTE = [
  'diagnose',
  'architekt',
  'bedarfe',
  'retrieval',
  'kurator',
  'speichern',
  'zusammenbau',
] as const;
export type Schrittname = (typeof SCHRITTE)[number];

export type Melder = (ereignis: Ereignis) => void;
