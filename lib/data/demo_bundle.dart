import '../model/exercise.dart';
import '../model/library.dart';
import '../model/program.dart';
import '../model/progression.dart';
import '../model/set_spec.dart';
import '../model/target.dart';

/// Ein Programm, das jede Funktion der App einmal zeigt.
///
/// Kein Inhalt, den jemand üben soll — ein Prüfstand. Jede Übung und jede
/// Phase ist nach dem benannt, was sie vorführt, damit beim Durchklicken
/// sofort klar ist, was gerade geprüft wird: alle vier Zieltypen, Last,
/// mehrere Sätze, Pausen, Notiz, Kür, beide Steigerungsarten, beide
/// Tagespläne, Medien.
///
/// Wird nicht beim Start geladen. Die Bibliothek startet leer und wächst aus
/// dem, was der Nutzer importiert — ein automatisch eingespieltes Demoprogramm
/// würde genau den Tag-Pool verunreinigen, aus dem der Chat-Import schöpft.
/// Deshalb ein Menüeintrag in der Übungsbibliothek, direkt neben dem
/// Zurücksetzen: erst leeren, dann laden, dann prüfen.
///
/// Alle Kennungen beginnen mit `demo-`. So ist im Bestand auf einen Blick zu
/// sehen, was Prüfstand ist und was echter Inhalt.
Bundle demoBundle() => Bundle(
  exercises: _exercises,
  routines: _routines,
  programs: [_program],
);

// --- Übungen: jede zeigt etwas anderes --------------------------------------

const _exercises = <Exercise>[
  Exercise(
    id: 'demo-dauer',
    name: 'Zieltyp: Dauer',
    description:
        'Eine Übung mit Zeitziel. Der Player zählt herunter und zeigt die '
        'große Ziffer.\n'
        'Diese zweite Zeile prüft, ob mehrzeilige Anleitungen umgebrochen '
        'werden — description ist ein Feld, die Zeilen sind Darstellung.',
    benefits: ['Zeigt den Countdown', 'Zeigt den Umbruch mehrzeiliger Texte'],
    cues: ['Ein Hinweis, der während der Ausführung steht.'],
    equipment: ['Stoppuhr'],
    tags: ['demo', 'dauer', 'player'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 60))],
  ),
  Exercise(
    id: 'demo-wdh',
    name: 'Zieltyp: Wiederholungen',
    description: 'Eine Übung mit Wiederholungsziel, dazu eine Last in Kilo.',
    benefits: ['Zeigt Wiederholungen und Last nebeneinander'],
    equipment: ['Kurzhantel'],
    tags: ['demo', 'wiederholungen', 'last'],
    defaultSets: [SetSpec(target: RepsTarget(reps: 10))],
  ),
  Exercise(
    id: 'demo-quote',
    name: 'Zieltyp: Quote',
    description:
        'Eine Übung mit Trefferquote: von n Versuchen müssen m sitzen. Im '
        'Player lässt sich jeder Versuch abhaken.',
    benefits: ['Zeigt das Abhaken einzelner Versuche'],
    tags: ['demo', 'quote'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 10, required: 7))],
  ),
  Exercise(
    id: 'demo-offen',
    name: 'Zieltyp: offen',
    description:
        'Eine Übung ohne festes Maß. Der Player stellt stattdessen die Frage '
        'aus dem Ziel und wartet, bis von Hand weitergeschaltet wird.',
    benefits: ['Zeigt den offenen Zieltyp mit Rückfrage'],
    tags: ['demo', 'offen'],
    defaultSets: [
      SetSpec(target: OpenTarget(prompt: 'Was ist dir dabei aufgefallen?')),
    ],
  ),
  Exercise(
    id: 'demo-medien',
    name: 'Medien und langer Text',
    description:
        'Diese Übung trägt zwei Medieneinträge — ein Bild und eine Animation. '
        'Beide zeigen auf entfernte Adressen, die es nicht gibt.\n'
        'Erwartet wird kein kaputtes Bild, sondern ein Platzhalter mit der '
        'Adresse. Genau das ist die Prüfung.\n'
        'Dazu ein absichtlich langer Absatz, damit sichtbar wird, wie sich '
        'der Text über mehrere Zeilen verhält und ob die Kästen mitwachsen '
        'statt abzuschneiden.',
    benefits: [
      'Zeigt den Medien-Platzhalter',
      'Zeigt mehrere Vorteile untereinander',
      'Zeigt den Umbruch langer Absätze',
    ],
    cues: ['Erster Hinweis.', 'Zweiter Hinweis.'],
    equipment: ['Etwas', 'Noch etwas', 'Und ein drittes Ding'],
    media: [
      Media(kind: MediaKind.image, uri: 'https://example.invalid/bild.png'),
      Media(
        kind: MediaKind.animation,
        uri: 'https://example.invalid/animation.gif',
      ),
    ],
    tags: ['demo', 'medien', 'text'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 30))],
  ),
  Exercise(
    id: 'demo-karg',
    name: 'Nur das Nötigste',
    description: 'Kein Vorteil, kein Hinweis, kein Material, ein Tag.',
    tags: ['demo'],
  ),
];

// --- Einheiten: jede zeigt eine andere Zusammensetzung ----------------------

const _routines = <Routine>[
  Routine(
    id: 'demo-e1',
    name: 'Alle vier Zieltypen',
    description: 'Eine Einheit, die jeden Zieltyp einmal durchspielt.',
    slots: [
      ExerciseSlot(
        exerciseId: 'demo-dauer',
        sets: [SetSpec(target: DurationTarget(seconds: 90))],
        restSeconds: 30,
        note: 'Eine Notiz am Slot — das, was nur für diesen Plan gilt.',
      ),
      ExerciseSlot(
        exerciseId: 'demo-wdh',
        // Drei Sätze mit steigender Last: zeigt mehrere Sätze an einem Slot.
        sets: [
          SetSpec(target: RepsTarget(reps: 12), load: Load(value: 10, unit: 'kg')),
          SetSpec(target: RepsTarget(reps: 10), load: Load(value: 12.5, unit: 'kg')),
          SetSpec(target: RepsTarget(reps: 8), load: Load(value: 15, unit: 'kg')),
        ],
        restSeconds: 90,
      ),
      ExerciseSlot(
        exerciseId: 'demo-quote',
        sets: [SetSpec(target: QuotaTarget(attempts: 10, required: 7))],
      ),
      ExerciseSlot(
        exerciseId: 'demo-offen',
        sets: [
          SetSpec(target: OpenTarget(prompt: 'Was ist dir aufgefallen?')),
        ],
        // Kür: darf übersprungen werden, ohne dass der Tag unvollständig gilt.
        optional: true,
      ),
    ],
  ),
  Routine(
    id: 'demo-e2',
    name: 'Steigerung über die Wochen',
    description: 'Zeigt, wie sich Sätze von Woche zu Woche verändern.',
    slots: [
      ExerciseSlot(
        exerciseId: 'demo-dauer',
        sets: [SetSpec(target: DurationTarget(seconds: 60))],
        // Jede Woche fünfzehn Sekunden mehr, gedeckelt bei zwei Minuten.
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 15,
          cap: 120,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'demo-wdh',
        sets: [
          SetSpec(target: RepsTarget(reps: 8), load: Load(value: 20, unit: 'kg')),
        ],
        // Alle zwei Wochen zweieinhalb Kilo mehr.
        progression: LinearProgression(
          field: ProgressionField.load,
          amount: 2.5,
          everyWeeks: 2,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'demo-quote',
        sets: [SetSpec(target: QuotaTarget(attempts: 10, required: 5))],
        // Woche für Woche fest vorgegeben statt gerechnet.
        progression: TableProgression(
          perWeek: [
            SetSpec(target: QuotaTarget(attempts: 10, required: 5)),
            SetSpec(target: QuotaTarget(attempts: 10, required: 7)),
            null, // unverändert
            SetSpec(target: QuotaTarget(attempts: 12, required: 10)),
          ],
        ),
      ),
    ],
  ),
  Routine(
    id: 'demo-e3',
    name: 'Kurz und karg',
    slots: [
      ExerciseSlot(
        exerciseId: 'demo-karg',
        sets: [SetSpec(target: OpenTarget())],
      ),
      ExerciseSlot(
        exerciseId: 'demo-medien',
        sets: [SetSpec(target: DurationTarget(seconds: 45))],
      ),
    ],
  ),
];

// --- Das Programm: drei Phasen, zwei Arten von Tagesplan --------------------

const _program = Program(
  id: 'demo-programm',
  name: 'Testprogramm: alle Funktionen',
  description:
      'Kein Übungsplan, sondern ein Prüfstand. Jede Phase führt etwas anderes '
      'vor — Zieltypen, Steigerung, Tagespläne. Zum Ansehen, nicht zum Üben.',
  domain: 'demo',
  tags: ['demo', 'dauer', 'wiederholungen', 'quote', 'offen'],
  rationale:
      'Diese Begründung steht hier, damit sichtbar ist, wo der Text landet, '
      'den die KI als "rationale" schreibt — der Teil, der aus einer '
      'Übungsliste eine nachvollziehbare Diagnose macht.',
  phases: [
    Phase(
      id: 'demo-p1',
      name: 'Phase 1: Woche mit Pausentagen',
      description: 'Ein Zyklus über sieben Tage, drei davon frei.',
      goal: 'Zeigt den Wochenzyklus mit benannten Pausentagen.',
      weeks: 2,
      schedule: CycleSchedule(
        days: [
          DaySlot(routineId: 'demo-e1'),
          DaySlot(label: 'Pause'),
          DaySlot(routineId: 'demo-e2'),
          DaySlot(label: 'Pause'),
          DaySlot(routineId: 'demo-e3'),
          DaySlot(routineId: 'demo-e1'),
          DaySlot(label: 'Pause'),
        ],
      ),
    ),
    Phase(
      id: 'demo-p2',
      name: 'Phase 2: Steigerung über vier Wochen',
      description:
          'Derselbe Zyklus vier Wochen lang. Die Sätze verändern sich von '
          'Woche zu Woche — linear beim Ziel, linear bei der Last, nach '
          'Tabelle bei der Quote.',
      goal: 'Zeigt, dass die Steigerung innerhalb der Phase greift.',
      weeks: 4,
      schedule: CycleSchedule(
        days: [
          DaySlot(routineId: 'demo-e2'),
          DaySlot(label: 'Frei'),
          DaySlot(routineId: 'demo-e2'),
        ],
      ),
    ),
    Phase(
      id: 'demo-p3',
      name: 'Phase 3: jeden Tag dasselbe',
      description: 'Der einfache Fall — eine Einheit, fünf Tage die Woche.',
      goal: 'Zeigt den zweiten Typ Tagesplan.',
      weeks: 1,
      schedule: EveryDaySchedule(routineId: 'demo-e3', daysPerWeek: 5),
    ),
  ],
);
