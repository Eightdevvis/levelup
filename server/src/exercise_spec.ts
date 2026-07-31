/**
 * Was eine gute Übung ausmacht — und die Prüfung dazu.
 *
 * Die Übung ist der Baustein, aus dem alles andere besteht: Einheiten sind
 * Listen von Übungen, Phasen sind Folgen von Einheiten, der Pool besteht aus
 * ihnen. Ein schlechter Plan ist ärgerlich und wird weggeworfen. Eine schlechte
 * Übung landet im Pool und wird von da an weiterverwendet.
 *
 * Deshalb steht die Regel hier nicht nur als Text, sondern auch als Prüfung.
 * Formulierter Text wird weich ausgelegt; eine Prüfung nicht. Sie kann nicht
 * beurteilen, ob eine Übung *sinnvoll* ist — nur ob sie die Form hat, die wir
 * verlangen. Das reicht für die Fehler, die tatsächlich vorkommen.
 */

/** Wird in den Plan-Prompt eingesetzt, damit es nur eine Quelle gibt. */
export const EXERCISE_SPEC = `
WAS EINE ÜBUNG IST

Eine Übung ist EINE Sache, die man tut. Nicht ein Ablauf, nicht ein Tag, nicht
eine Anleitung mit mehreren Schritten.

"Grundstellung blind ertasten" ist eine Übung. "Erst Hände auflegen, dann
Augen schließen, dann jede Taste einzeln ertasten, danach fünf Wörter tippen"
ist vier Übungen — oder eine Übung, deren instructions dieselbe eine Sache
genauer beschreiben. Der Unterschied: kann man aufhören, wenn Schritt zwei
sitzt, und den Rest morgen machen? Dann sind es mehrere Übungen.

instructions erklären, wie man die eine Sache richtig macht. Sie sind kein
Programm und keine Reihenfolge von Aufgaben. Drei bis fünf Zeilen reichen,
höchstens sechs.

Der Name benennt die Sache, er beschreibt sie nicht. "Blattlesen im Viervierteltakt"
ist ein Name. "Erst Takt klopfen und dann die Melodie lesen" ist keiner.

Eine Einheit besteht aus mehreren Übungen — meist drei bis sechs. Eine Einheit
mit einer einzigen, großen Übung ist fast immer falsch geschnitten: sie ist in
Wahrheit eine Einheit aus mehreren Übungen, die zusammengeschrieben wurde.

Jede Übung braucht ein "summary" (ein bis zwei Sätze, worum es geht) und
mindestens einen Eintrag in "benefits" (wofür das gut ist). Ohne beides steht
der Nutzer vor einem Titel und weiß nicht, warum er das tun soll.
`.trim();

interface RawExercise {
  id?: unknown;
  name?: unknown;
  summary?: unknown;
  instructions?: unknown;
  benefits?: unknown;
  requirements?: unknown;
}

const MAX_INSTRUCTIONS = 6;
const MAX_NAME_WORDS = 8;

/**
 * Wörter, die im NAMEN einen Ablauf verraten.
 *
 * In den instructions sind sie normal ("halte den Bogen, dann ziehe durch") —
 * im Namen bedeuten sie fast immer, dass zwei Übungen zusammengeschrieben
 * wurden.
 */
const ABLAUF_IM_NAMEN = /\b(dann|danach|anschlie(ß|ss)end|zuerst|erst\s|sp(ä|ae)ter|zum\s+schluss)\b/i;

/**
 * Prüft eine einzelne Übung und liefert Klartext-Beanstandungen.
 *
 * Leer heißt: in Ordnung. Die Meldungen gehen unverändert an das Modell
 * zurück, sind also so formuliert, dass sie sagen, was zu tun ist.
 */
export function checkExercise(raw: unknown): string[] {
  if (typeof raw !== 'object' || raw === null) return ['Keine Übung.'];
  const ex = raw as RawExercise;
  const id = typeof ex.id === 'string' ? ex.id : '(ohne id)';
  const probleme: string[] = [];

  const name = typeof ex.name === 'string' ? ex.name.trim() : '';
  if (name.length < 3) {
    probleme.push(`${id}: braucht einen Namen.`);
  } else {
    if (ABLAUF_IM_NAMEN.test(name)) {
      probleme.push(
        `${id}: der Name "${name}" beschreibt einen Ablauf. Eine Übung ist ` +
          `EINE Sache — teile sie in mehrere Übungen auf.`,
      );
    }
    if (name.split(/\s+/).length > MAX_NAME_WORDS) {
      probleme.push(
        `${id}: der Name ist zu lang. Er soll die Sache benennen, nicht ` +
          `beschreiben — das gehört in "summary".`,
      );
    }
  }

  const summary = typeof ex.summary === 'string' ? ex.summary.trim() : '';
  if (summary.length < 10) {
    probleme.push(`${id}: "summary" fehlt — ein bis zwei Sätze, worum es geht.`);
  }

  const instructions = Array.isArray(ex.instructions)
    ? ex.instructions.filter((x) => typeof x === 'string')
    : [];
  if (instructions.length > MAX_INSTRUCTIONS) {
    probleme.push(
      `${id}: ${instructions.length} Anleitungspunkte. Mehr als ` +
        `${MAX_INSTRUCTIONS} heißt fast immer, dass hier mehrere Übungen ` +
        `zusammengeschrieben wurden. Teile sie auf.`,
    );
  }

  const benefits = Array.isArray(ex.benefits)
    ? ex.benefits.filter((x) => typeof x === 'string' && x.trim().length > 0)
    : [];
  if (benefits.length === 0) {
    probleme.push(`${id}: "benefits" fehlt — wofür ist die Übung gut?`);
  }

  // Material wird hier bewusst NICHT geprüft. Der erste Versuch verglich
  // "requirements" mit dem übrigen Text und meldete bei einem echten Plan 25
  // Beanstandungen — darunter "Tastatur" und "Stuhl" bei einer Tipp-Übung.
  // Genau das ist der Fall "was jemand hat, der diese Fähigkeit übt", und eine
  // mechanische Prüfung kann ihn nicht vom echten Problem unterscheiden. Ein
  // Prüfer, der überwiegend Fehlalarme erzeugt, ist schlechter als keiner: er
  // löst Korrekturrunden aus, in denen Richtiges umgeschrieben wird. Die
  // Materialregel bleibt deshalb reine Prompt-Regel.

  return probleme;
}

/**
 * Prüft alle Übungen eines Bundles.
 *
 * Zusätzlich zur Einzelprüfung: eine Einheit aus genau einer Übung ist der
 * Fehler, der den Tagesplan unlesbar gemacht hat, und fällt nur auf, wenn man
 * die Listen mitansieht.
 */
export function checkBundle(document: Record<string, unknown>): string[] {
  const probleme: string[] = [];

  const exercises = Array.isArray(document.exercises) ? document.exercises : [];
  for (const ex of exercises) probleme.push(...checkExercise(ex));

  const routines = Array.isArray(document.routines) ? document.routines : [];
  for (const routine of routines) {
    if (typeof routine !== 'object' || routine === null) continue;
    const r = routine as { id?: unknown; slots?: unknown };
    const slots = Array.isArray(r.slots) ? r.slots : [];
    if (slots.length === 1) {
      probleme.push(
        `Liste "${String(r.id)}" besteht aus einer einzigen Übung. Eine ` +
          `Einheit hat meist drei bis sechs — vermutlich steckt hier eine ` +
          `zusammengeschriebene Übung drin, die aufzuteilen ist.`,
      );
    }
  }

  return probleme;
}
