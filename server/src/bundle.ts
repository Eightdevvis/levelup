import { positionsschluessel } from './bedarfe';
import type {
  Architektur,
  Eingabe,
  Problemmodell,
  UebungDatensatz,
  Uebungsreferenz,
} from './typen';

/**
 * Die einzige Übersetzung im ganzen System: Spec-Objekte → Bundle der App
 * (Arbeitsliste 10).
 *
 * Deutsche Feldnamen wandern durch Prompts, Datenbank und Prüfung; hier, an
 * der Grenze zur App, werden sie einmal zu den englischen des Datenmodells.
 * Jede weitere Übersetzungsstelle wäre eine Fehlerquelle mehr.
 */

/** 2 seit dem Umbau des Übungsobjekts — siehe `kBundleVersion` in der App. */
export const BUNDLE_VERSION = 2;

interface Media {
  kind: 'image' | 'animation';
  uri: string;
}

interface Exercise {
  id: string;
  name: string;
  /** Eine Handlungsanweisung, ein Feld. `summary` und `instructions` waren
   *  getrennt und sagten dasselbe (Spec §2.1). */
  description: string;
  benefits: string[];
  tags: string[];
  equipment: string[];
  media: Media[];
}

interface SetSpec {
  target: { kind: 'duration'; seconds: number };
}

interface ExerciseSlot {
  exerciseId: string;
  sets: SetSpec[];
  note?: string;
}

interface Routine {
  id: string;
  name: string;
  description?: string;
  slots: ExerciseSlot[];
}

interface DaySlot {
  routineId?: string;
  label?: string;
}

interface AppPhase {
  id: string;
  name: string;
  weeks: number;
  schedule: { kind: 'cycle'; days: DaySlot[] };
  description?: string;
  goal?: string;
}

interface Program {
  id: string;
  name: string;
  description?: string;
  domain: string;
  tags: string[];
  phases: AppPhase[];
  rationale?: string;
}

export interface Bundle {
  version: number;
  personalNote?: string;
  exercises: Exercise[];
  routines: Routine[];
  programs: Program[];
}

export interface Zusammenbau {
  architektur: Architektur;
  referenzen: Map<string, Uebungsreferenz>;
  uebungen: Map<string, UebungDatensatz>;
  problemmodell: Problemmodell;
  eingabe: Eingabe;
  programmId: string;
  /** Tags, die im Vokabular als Tätigkeit geführt werden. Daraus wird
   *  `Exercise.domain` — die App hat kein eigenes Bereichsfeld. */
  taetigkeiten: Set<string>;
}

export function baueBundle(z: Zusammenbau): Bundle {
  const benutzte = new Set<string>();
  const routines: Routine[] = [];
  const phasen: AppPhase[] = [];

  z.architektur.phasen.forEach((phase, p) => {
    const routineIds: string[] = [];

    phase.einheiten.forEach((einheit, e) => {
      const slots: ExerciseSlot[] = [];

      einheit.uebungen.forEach((_, i) => {
        const referenz = z.referenzen.get(positionsschluessel(p, e, i));
        // Eine Position ohne Entscheidung gäbe in der App eine Übung, auf die
        // nichts zeigt. Lieber fehlt der Slot als dass er ins Leere weist.
        if (referenz === undefined || !z.uebungen.has(referenz.uebung_id)) return;

        benutzte.add(referenz.uebung_id);
        slots.push({
          exerciseId: referenz.uebung_id,
          sets: [{ target: { kind: 'duration', seconds: referenz.dauer_min * 60 } }],
          ...(referenz.kontext_hinweis === null ? {} : { note: referenz.kontext_hinweis }),
        });
      });

      if (slots.length === 0) return;
      const id = `${z.programmId}-p${p + 1}-e${e + 1}`;
      routines.push({ id, name: `${phase.titel} · Einheit ${e + 1}`, slots });
      routineIds.push(id);
    });

    phasen.push({
      id: `${z.programmId}-p${p + 1}`,
      name: phase.titel,
      // Eine Phase, deren Einheiten sich unterscheiden, ließe sich mit
      // weeks > 1 nicht abbilden — Woche 2 spielte wieder Einheit 1–3.
      // Deshalb ist der Zyklus so lang wie die ganze Phase.
      weeks: 1,
      schedule: { kind: 'cycle', days: verteile(routineIds, z.eingabe.tage_pro_woche) },
      description: phase.ziel,
      goal: `${phase.austrittskriterium} · Prüfung: ${phase.pruefung}`,
    });
  });

  const alleTags = [...benutzte].flatMap((id) => z.uebungen.get(id)?.tags ?? []);
  const domain = ersteTaetigkeit(alleTags, z.taetigkeiten);

  const programm: Program = {
    id: z.programmId,
    name: z.architektur.programm_titel,
    description: z.architektur.programm_beschreibung,
    domain,
    tags: [...new Set(alleTags)],
    phases: phasen,
    rationale: begruendung(z.problemmodell),
  };

  return {
    version: BUNDLE_VERSION,
    personalNote: persoenlich(z.problemmodell),
    exercises: [...benutzte].map((id) => zuExercise(z.uebungen.get(id)!, z.taetigkeiten)),
    routines,
    programs: [programm],
  };
}

/**
 * Legt die Einheiten auf Tage, mit Pausen dazwischen.
 *
 * Der Rhythmus kommt aus `tage_pro_woche`: bei drei Tagen liegen die
 * Einheiten auf Tag 1, 4 und 6 der Woche, nicht auf 1, 2, 3 mit vier Tagen
 * Pause am Stück. Angebrochene Wochen werden mit Pausentagen aufgefüllt,
 * damit sich der Wochenrhythmus über die Phase hinweg nicht verschiebt.
 */
export function verteile(routineIds: readonly string[], tageProWoche: number): DaySlot[] {
  const proWoche = Math.min(7, Math.max(1, Math.round(tageProWoche)));
  const muster = Array.from({ length: 7 }, (_, i) => (i * proWoche) % 7 < proWoche);

  const tage: DaySlot[] = [];
  let naechste = 0;
  while (naechste < routineIds.length) {
    for (const trainingstag of muster) {
      if (trainingstag && naechste < routineIds.length) {
        tage.push({ routineId: routineIds[naechste++] });
      } else {
        tage.push({ label: 'Pause' });
      }
    }
  }
  return tage;
}

function zuExercise(uebung: UebungDatensatz, taetigkeiten: Set<string>): Exercise {
  const media: Media[] = [];
  if (uebung.bild !== null) media.push({ kind: 'image', uri: uebung.bild });
  if (uebung.animation !== null) media.push({ kind: 'animation', uri: uebung.animation });

  return {
    id: uebung.id,
    name: uebung.titel,
    description: uebung.anleitung,
    benefits: [uebung.benefit],
    tags: sortiertNachTaetigkeit(uebung.tags, taetigkeiten),
    equipment: uebung.equipment,
    media,
  };
}

/**
 * Das Tätigkeits-Tag nach vorn.
 *
 * Die App hat kein Bereichsfeld mehr — sie liest die Tätigkeit als ersten Tag.
 * Steht dort ein beliebiger anderer, gruppiert die Bibliothek nach „aufnahme"
 * statt nach „geige".
 */
function sortiertNachTaetigkeit(tags: string[], taetigkeiten: Set<string>): string[] {
  const index = tags.findIndex((t) => taetigkeiten.has(t));
  if (index <= 0) return tags;
  return [tags[index], ...tags.filter((_, i) => i !== index)];
}

/** `Exercise.domain` ist ein freies Tag. Genommen wird das erste, das im
 *  Vokabular als Tätigkeit geführt wird — sonst der Vorgabewert der App. */
function ersteTaetigkeit(tags: readonly string[], taetigkeiten: Set<string>): string {
  return tags.find((t) => taetigkeiten.has(t)) ?? 'allgemein';
}

/** Warum der Plan so aussieht, wie er aussieht — ohne persönliche Angaben,
 *  denn das Programm kann geteilt werden. */
function begruendung(p: Problemmodell): string {
  return [
    p.kernproblem,
    `Vermutete Ursache: ${p.vermutete_ursache}`,
    `Rückkopplung (${p.rueckkopplung.quelle}, ${p.rueckkopplung.status}): ${p.rueckkopplung.begruendung}`,
    `Wie ${p.vorbild.wer} es gelernt hat: ${p.vorbild.methode}`,
  ].join('\n\n');
}

/** Bleibt auf dem Gerät. Wird beim Teilen entfernt — deshalb steht hier, was
 *  nur diesen einen Menschen angeht. */
function persoenlich(p: Problemmodell): string {
  const faehigkeiten =
    p.grundfaehigkeiten.length > 0
      ? `\n\nDaran hängt es zuerst: ${p.grundfaehigkeiten.join(', ')}.`
      : '';
  return `${p.kernproblem}\n\n${p.vermutete_ursache}${faehigkeiten}`;
}
