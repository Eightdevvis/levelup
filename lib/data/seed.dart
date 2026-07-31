import '../model/exercise.dart';
import '../model/library.dart';
import '../model/program.dart';
import '../model/progression.dart';
import '../model/set_spec.dart';
import '../model/target.dart';

/// Startinhalte.
///
/// Vier Domänen mit voller Absicht: Geige, Gehörbildung, Kraft und Zeichnen
/// laufen durch exakt dieselben Objekte. Wenn eine davon Sonderbehandlung
/// bräuchte, wäre das Modell zu eng.
Bundle seedBundle() => Bundle(
  exercises: [
    ..._violinExercises,
    ..._earExercises,
    ..._strengthExercises,
    ..._artExercises,
  ],
  routines: [
    ..._violinRoutines,
    ..._earRoutines,
    ..._strengthRoutines,
    ..._artRoutines,
  ],
  programs: [_bachProgram, _earProgram, _strengthProgram, _artProgram],
);

// ---------------------------------------------------------------------------
// Geige / Notation
// ---------------------------------------------------------------------------

final _violinExercises = <Exercise>[
  const Exercise(
    id: 'v-notenkarten',
    name: 'Notenkarten auf Zeit',
    domain: 'geige',
    summary:
        'Einzelne Noten auf Karten so lange lesen, bis der Griff kommt, bevor '
        'der Name gedacht ist.',
    instructions: [
      'Kartenstapel im gewünschten Schlüssel mischen.',
      'Karte aufdecken, sofort den Griff auf dem Griffbrett zeigen.',
      'Erst danach den Notennamen laut sagen — nicht umgekehrt.',
      'Karte auf "sitzt" oder "nochmal" legen, keine Pause zum Grübeln.',
    ],
    benefits: [
      'Verlagert das Lesen von Rechnen auf Erkennen.',
      'Baut die direkte Verbindung Notenbild → Griff, ohne Umweg über den Namen.',
    ],
    cues: ['Griff zuerst, Name danach.', 'Tempo vor Perfektion.'],
    requirements: ['Notenkarten', 'Instrument'],
    tags: ['notation', 'lesen'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 40, required: 30))],
  ),
  const Exercise(
    id: 'v-rhythmus-klatschen',
    name: 'Rhythmus vom Blatt klatschen',
    domain: 'geige',
    summary:
        'Rhythmen ohne Tonhöhe lesen — die halbe Notation, isoliert geübt.',
    instructions: [
      'Metronom auf ein ruhiges Tempo stellen.',
      'Takt anschauen, einmal still mitzählen.',
      'Rhythmus klatschen und dabei laut zählen.',
      'Bei Fehler nicht anhalten — im nächsten Takt wieder einsteigen.',
    ],
    benefits: [
      'Trennt das Rhythmusproblem vom Tonhöhenproblem.',
      'Macht komplexe Bach-Figuren lesbar, bevor das Instrument dazukommt.',
    ],
    cues: ['Laut zählen, immer.'],
    requirements: ['Metronom', 'Notenmaterial'],
    tags: ['notation', 'rhythmus'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 300))],
  ),
  const Exercise(
    id: 'v-vom-blatt-singen',
    name: 'Vom Blatt singen',
    domain: 'geige',
    summary:
        'Die Melodie singen, bevor sie gespielt wird — zwingt zur inneren '
        'Vorstellung statt zum Abgreifen.',
    instructions: [
      'Grundton am Instrument anspielen, dann Instrument weglegen.',
      'Melodie langsam singen, Finger dürfen mitzeigen.',
      'An unsicheren Stellen anhalten und das Intervall benennen.',
    ],
    benefits: [
      'Baut das innere Gehör für das, was auf dem Papier steht.',
      'Deckt auf, welche Stellen nur motorisch, nicht verstanden sind.',
    ],
    tags: ['notation', 'gehoer'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 300))],
  ),
  const Exercise(
    id: 'v-tonleiter-metronom',
    name: 'Tonleitern mit Metronom',
    domain: 'geige',
    summary: 'Tonleitern in wechselnden Tonarten, Tempo als messbare Größe.',
    instructions: [
      'Tonart des Tages wählen, Vorzeichen laut benennen.',
      'Zwei Oktaven auf und ab, gebundene Viertel.',
      'Tempo erst erhöhen, wenn drei Durchgänge sauber sind.',
    ],
    benefits: [
      'Verbindet Tonartwissen mit der Hand statt nur mit dem Kopf.',
      'Gibt der Übung eine harte Zahl, an der Fortschritt sichtbar wird.',
    ],
    cues: ['Vorzeichen laut sagen.'],
    requirements: ['Metronom'],
    tags: ['technik', 'tonarten'],
    defaultSets: [
      SetSpec(
        target: DurationTarget(seconds: 480),
        load: Load(value: 60, unit: 'bpm'),
      ),
    ],
  ),
  const Exercise(
    id: 'v-tonarten-theorie',
    name: 'Tonarten und Quintenzirkel',
    domain: 'geige',
    summary:
        'Vorzeichen, Stufen und Verwandtschaften — das Gerüst, an dem Notation '
        'erst Bedeutung bekommt.',
    instructions: [
      'Tonart des Tages: Vorzeichen aus dem Kopf aufschreiben.',
      'Stufendreiklänge notieren und benennen.',
      'Parallele und Dominanttonart dazu bestimmen.',
    ],
    benefits: [
      'Verwandelt zufällige Vorzeichen in erwartbare Muster.',
      'Reduziert die Menge, die beim Lesen gemerkt werden muss.',
    ],
    tags: ['theorie'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 600))],
  ),
  const Exercise(
    id: 'v-intervalle-griffbrett',
    name: 'Intervalle auf dem Griffbrett',
    domain: 'geige',
    summary: 'Notiertes Intervall sehen, sofort greifen.',
    instructions: [
      'Zwei Noten aufdecken.',
      'Intervall benennen und direkt greifen.',
      'Dann spielen und gegen die Vorstellung prüfen.',
    ],
    benefits: [
      'Macht aus Einzelnoten Beziehungen — die Einheit, in der man wirklich liest.',
    ],
    tags: ['notation', 'technik'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 24, required: 18))],
  ),
  const Exercise(
    id: 'v-bach-analyse',
    name: 'Bach-Takt analysieren',
    domain: 'geige',
    summary:
        'Einen einzelnen Takt schriftlich auseinandernehmen, ohne ihn zu spielen.',
    instructions: [
      'Einen Takt abschreiben.',
      'Harmonische Funktion und Stufe eintragen.',
      'Motiv markieren und benennen, wo es wiederkehrt.',
    ],
    benefits: [
      'Bach wird lesbar als Struktur statt als Notenwand.',
      'Was analysiert ist, muss nicht auswendig gelernt werden.',
    ],
    requirements: ['Notenpapier', 'Bleistift'],
    tags: ['theorie', 'bach'],
    defaultSets: [SetSpec(target: OpenTarget(prompt: 'ein Takt, schriftlich'))],
  ),
  const Exercise(
    id: 'v-bach-vomblatt',
    name: 'Bach vom Blatt, halbes Tempo',
    domain: 'geige',
    summary: 'Unbekannte Takte im Zeitlupentempo lesen, ohne vorher zu üben.',
    instructions: [
      'Vier neue Takte auswählen, nicht vorher anschauen.',
      'Metronom auf halbes Zieltempo.',
      'Durchspielen ohne anzuhalten, Fehler stehen lassen.',
      'Danach erst zurückgehen und die Stelle klären.',
    ],
    benefits: [
      'Trainiert genau das Lesen, nicht das Auswendigkönnen.',
      'Hält den Blick vorne statt an der Fehlerstelle.',
    ],
    cues: ['Nicht anhalten.', 'Blick eine Note voraus.'],
    tags: ['bach', 'lesen'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 900))],
  ),
];

final _violinRoutines = <Routine>[
  const Routine(
    id: 'v-r-notation-taeglich',
    name: 'Notation täglich',
    description: 'Kurzer Block, jeden Tag gleich — Aufbau der Lesegrundlage.',
    slots: [
      ExerciseSlot(
        exerciseId: 'v-notenkarten',
        sets: [SetSpec(target: QuotaTarget(attempts: 40, required: 28))],
        restSeconds: 30,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 2,
          cap: 38,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'v-rhythmus-klatschen',
        sets: [SetSpec(target: DurationTarget(seconds: 300))],
        restSeconds: 30,
      ),
      ExerciseSlot(
        exerciseId: 'v-tonleiter-metronom',
        sets: [
          SetSpec(
            target: DurationTarget(seconds: 480),
            load: Load(value: 60, unit: 'bpm'),
          ),
        ],
        note: 'Tonart nach Quintenzirkel durchwechseln.',
        progression: LinearProgression(
          field: ProgressionField.load,
          amount: 4,
          cap: 96,
        ),
      ),
    ],
  ),
  const Routine(
    id: 'v-r-theorie',
    name: 'Theorie am Schreibtisch',
    description: 'Ohne Instrument — Struktur statt Motorik.',
    slots: [
      ExerciseSlot(
        exerciseId: 'v-tonarten-theorie',
        sets: [SetSpec(target: DurationTarget(seconds: 600))],
        restSeconds: 60,
      ),
      ExerciseSlot(
        exerciseId: 'v-intervalle-griffbrett',
        sets: [SetSpec(target: QuotaTarget(attempts: 24, required: 16))],
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          cap: 22,
        ),
      ),
    ],
  ),
  const Routine(
    id: 'v-r-instrument',
    name: 'Am Instrument',
    description: 'Lesen mit Geige in der Hand.',
    slots: [
      ExerciseSlot(
        exerciseId: 'v-tonleiter-metronom',
        sets: [
          SetSpec(
            target: DurationTarget(seconds: 360),
            load: Load(value: 72, unit: 'bpm'),
          ),
        ],
        progression: LinearProgression(
          field: ProgressionField.load,
          amount: 4,
          cap: 108,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'v-vom-blatt-singen',
        sets: [SetSpec(target: DurationTarget(seconds: 300))],
        restSeconds: 30,
      ),
      ExerciseSlot(
        exerciseId: 'v-notenkarten',
        sets: [SetSpec(target: QuotaTarget(attempts: 40, required: 32))],
        optional: true,
      ),
    ],
  ),
  const Routine(
    id: 'v-r-bach',
    name: 'Bach-Block',
    description: 'Analyse und Lesen am echten Material.',
    slots: [
      ExerciseSlot(
        exerciseId: 'v-bach-analyse',
        sets: [SetSpec(target: OpenTarget(prompt: 'ein Takt, schriftlich'))],
        restSeconds: 60,
      ),
      ExerciseSlot(
        exerciseId: 'v-bach-vomblatt',
        sets: [SetSpec(target: DurationTarget(seconds: 900))],
        note: 'Immer neue Takte, nie die von gestern.',
      ),
      ExerciseSlot(
        exerciseId: 'v-rhythmus-klatschen',
        sets: [SetSpec(target: DurationTarget(seconds: 240))],
        optional: true,
      ),
    ],
  ),
];

final _bachProgram = Program(
  id: 'p-bach-lesen',
  name: 'Bach lesen lernen',
  domain: 'geige',
  author: 'Beispielplan',
  tags: const ['notation', 'theorie', 'bach'],
  description:
      'Zwölf Wochen von "ich kann spielen, aber nicht lesen" zu "ich kann mir '
      'einen unbekannten Bach-Satz erschließen".',
  rationale:
      'Das Problem ist nicht, mehr Bach zu spielen. Wer technisch spielen kann, '
      'aber an der Notation hängt, wird durch Wiederholung des Stücks nur '
      'besser im Auswendiglernen — die Leseschwäche bleibt. Der Plan setzt '
      'deshalb eine Ebene tiefer an: erst Notenerkennung automatisieren, dann '
      'das theoretische Gerüst nachziehen, das Notation überhaupt vorhersagbar '
      'macht, und erst zuletzt am echten Bach-Material lesen. Die ersten vier '
      'Wochen enthalten mit Absicht kein Bach.',
  phases: [
    const Phase(
      id: 'ph-1',
      name: 'Notation automatisieren',
      weeks: 4,
      description:
          'Jeden Tag derselbe kurze Block. Ziel ist Geschwindigkeit beim '
          'Erkennen, nicht Repertoire.',
      goal: '38 von 40 Notenkarten ohne Zögern.',
      schedule: EveryDaySchedule(
        routineId: 'v-r-notation-taeglich',
        daysPerWeek: 6,
      ),
    ),
    Phase(
      id: 'ph-2',
      name: 'Theorie nachziehen',
      weeks: 4,
      description:
          'Wechsel zwischen Schreibtisch und Instrument. Die Theorie senkt die '
          'Menge, die beim Lesen gemerkt werden muss.',
      goal: 'Vorzeichen jeder Dur-Tonart aus dem Kopf.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'v-r-theorie'),
          const DaySlot(routineId: 'v-r-instrument'),
          const DaySlot(routineId: 'v-r-theorie'),
          const DaySlot(routineId: 'v-r-instrument'),
          const DaySlot(routineId: 'v-r-notation-taeglich'),
          const DaySlot(routineId: 'v-r-instrument'),
          DaySlot.rest(),
        ],
      ),
    ),
    Phase(
      id: 'ph-3',
      name: 'Bach am Pult',
      weeks: 4,
      description: 'Jetzt erst das eigentliche Material — und zwar lesend.',
      goal: 'Einen unbekannten Satz im halben Tempo durchspielen.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'v-r-bach'),
          const DaySlot(routineId: 'v-r-instrument'),
          const DaySlot(routineId: 'v-r-bach'),
          DaySlot.rest(),
          const DaySlot(routineId: 'v-r-bach'),
          const DaySlot(routineId: 'v-r-theorie'),
          DaySlot.rest(),
        ],
      ),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Gehörbildung
// ---------------------------------------------------------------------------

final _earExercises = <Exercise>[
  const Exercise(
    id: 'g-intervalle',
    name: 'Intervalle hören',
    domain: 'gehoerbildung',
    summary: 'Zwei Töne, Intervall benennen — die Grundeinheit des Hörens.',
    instructions: [
      'Intervall abspielen lassen, nur einmal.',
      'Benennen, bevor nachgedacht wird.',
      'Erst danach kontrollieren und ggf. nachsingen.',
    ],
    benefits: ['Grundlage für Melodiediktat und Vom-Blatt-Singen.'],
    tags: ['gehoer'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 20, required: 14))],
  ),
  const Exercise(
    id: 'g-akkorde',
    name: 'Akkordqualität hören',
    domain: 'gehoerbildung',
    summary: 'Dur, Moll, vermindert, übermäßig unterscheiden.',
    instructions: [
      'Akkord abspielen.',
      'Qualität benennen.',
      'Bei Unsicherheit Terz herausgreifen und singen.',
    ],
    benefits: ['Macht Harmonik hörbar statt nur lesbar.'],
    tags: ['gehoer', 'harmonik'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 16, required: 11))],
  ),
  const Exercise(
    id: 'g-melodiediktat',
    name: 'Melodiediktat',
    domain: 'gehoerbildung',
    summary: 'Kurze Melodie hören und notieren.',
    instructions: [
      'Melodie zweimal hören.',
      'Rhythmus zuerst notieren, dann Tonhöhen.',
      'Gegen die Vorlage prüfen.',
    ],
    benefits: ['Verbindet Gehör und Notation in beide Richtungen.'],
    tags: ['gehoer', 'notation'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 8, required: 5))],
  ),
];

final _earRoutines = <Routine>[
  const Routine(
    id: 'g-r-taeglich',
    name: 'Gehör täglich',
    description: 'Fünfzehn Minuten, jeden Tag dieselbe Abfolge.',
    slots: [
      ExerciseSlot(
        exerciseId: 'g-intervalle',
        sets: [SetSpec(target: QuotaTarget(attempts: 20, required: 13))],
        restSeconds: 20,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          cap: 19,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'g-akkorde',
        sets: [SetSpec(target: QuotaTarget(attempts: 16, required: 10))],
        restSeconds: 20,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          cap: 15,
        ),
      ),
    ],
  ),
  const Routine(
    id: 'g-r-diktat',
    name: 'Diktat-Tag',
    slots: [
      ExerciseSlot(
        exerciseId: 'g-melodiediktat',
        sets: [SetSpec(target: QuotaTarget(attempts: 8, required: 4))],
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          everyWeeks: 2,
          cap: 7,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'g-intervalle',
        sets: [SetSpec(target: QuotaTarget(attempts: 20, required: 15))],
        optional: true,
      ),
    ],
  ),
];

final _earProgram = Program(
  id: 'p-gehoer',
  name: 'Gehörtraining Grundstock',
  domain: 'gehoerbildung',
  tags: const ['gehoer'],
  description: 'Acht Wochen tägliches Hören mit langsam steigender Hürde.',
  rationale:
      'Gehör wächst über Häufigkeit, nicht über Dauer. Deshalb kurze tägliche '
      'Einheiten und eine Trefferquote, die pro Woche nur um einen Treffer '
      'steigt — schnell genug für sichtbaren Fortschritt, langsam genug, dass '
      'die Quote erreichbar bleibt.',
  phases: [
    const Phase(
      id: 'g-ph-1',
      name: 'Tägliche Basis',
      weeks: 4,
      description: 'Immer dieselbe Liste, jeden Tag.',
      goal: 'Intervalle 17 von 20.',
      schedule: EveryDaySchedule(routineId: 'g-r-taeglich', daysPerWeek: 7),
    ),
    Phase(
      id: 'g-ph-2',
      name: 'Diktat dazu',
      weeks: 4,
      goal: 'Achttaktige Melodie in zwei Durchgängen notieren.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'g-r-taeglich'),
          const DaySlot(routineId: 'g-r-diktat'),
          const DaySlot(routineId: 'g-r-taeglich'),
          const DaySlot(routineId: 'g-r-diktat'),
          const DaySlot(routineId: 'g-r-taeglich'),
          DaySlot.rest(),
          DaySlot.rest(),
        ],
      ),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Kraft
// ---------------------------------------------------------------------------

final _strengthExercises = <Exercise>[
  const Exercise(
    id: 'k-kniebeuge',
    name: 'Kniebeuge',
    domain: 'kraft',
    summary: 'Grundübung für Beine und Rumpf.',
    instructions: [
      'Stand etwa schulterbreit, Zehen leicht nach außen.',
      'Hüfte zurück und runter, Knie folgen der Fußrichtung.',
      'Bis mindestens parallel, dann kontrolliert hoch.',
    ],
    benefits: ['Baut Beinkraft.', 'Überträgt auf fast jede andere Bewegung.'],
    cues: ['Brust hoch.', 'Ferse bleibt am Boden.'],
    requirements: ['Langhantel'],
    tags: ['unterkoerper'],
    defaultSets: [
      SetSpec(
        target: RepsTarget(reps: 8),
        load: Load(value: 40, unit: 'kg'),
      ),
    ],
  ),
  const Exercise(
    id: 'k-klimmzug',
    name: 'Klimmzug',
    domain: 'kraft',
    summary: 'Zug nach oben aus dem Hang.',
    instructions: [
      'Griff etwas breiter als schulterbreit.',
      'Schulterblätter zuerst nach unten ziehen.',
      'Hochziehen bis Kinn über der Stange, kontrolliert ablassen.',
    ],
    benefits: ['Rücken und Griffkraft.'],
    requirements: ['Klimmzugstange'],
    tags: ['oberkoerper'],
    defaultSets: [SetSpec(target: RepsTarget(reps: 5))],
  ),
  const Exercise(
    id: 'k-liegestuetz',
    name: 'Liegestütz',
    domain: 'kraft',
    summary: 'Druckbewegung ohne Geräte.',
    instructions: [
      'Hände unter den Schultern, Körper auf einer Linie.',
      'Ellbogen etwa 45 Grad zum Körper.',
      'Brust bis knapp über den Boden.',
    ],
    benefits: ['Brust, Trizeps, Rumpfspannung.'],
    tags: ['oberkoerper'],
    defaultSets: [SetSpec(target: RepsTarget(reps: 12))],
  ),
  const Exercise(
    id: 'k-plank',
    name: 'Unterarmstütz',
    domain: 'kraft',
    summary: 'Statische Rumpfspannung.',
    instructions: [
      'Unterarme unter den Schultern.',
      'Becken leicht kippen, Gesäß anspannen.',
      'Halten, ruhig weiteratmen.',
    ],
    benefits: ['Stabiler Rumpf.'],
    tags: ['rumpf'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 45))],
  ),
];

final _strengthRoutines = <Routine>[
  const Routine(
    id: 'k-r-a',
    name: 'Tag A — Drücken',
    slots: [
      ExerciseSlot(
        exerciseId: 'k-kniebeuge',
        sets: [
          SetSpec(
            target: RepsTarget(reps: 8),
            load: Load(value: 40, unit: 'kg'),
          ),
          SetSpec(
            target: RepsTarget(reps: 8),
            load: Load(value: 40, unit: 'kg'),
          ),
          SetSpec(
            target: RepsTarget(reps: 8),
            load: Load(value: 40, unit: 'kg'),
          ),
        ],
        restSeconds: 120,
        progression: LinearProgression(
          field: ProgressionField.load,
          amount: 2.5,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'k-liegestuetz',
        sets: [
          SetSpec(target: RepsTarget(reps: 10)),
          SetSpec(target: RepsTarget(reps: 10)),
          SetSpec(target: RepsTarget(reps: 10)),
        ],
        restSeconds: 90,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          cap: 20,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'k-plank',
        sets: [
          SetSpec(target: DurationTarget(seconds: 45)),
          SetSpec(target: DurationTarget(seconds: 45)),
        ],
        restSeconds: 60,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 5,
          cap: 120,
        ),
      ),
    ],
  ),
  const Routine(
    id: 'k-r-b',
    name: 'Tag B — Ziehen',
    slots: [
      ExerciseSlot(
        exerciseId: 'k-klimmzug',
        sets: [
          SetSpec(target: RepsTarget(reps: 4)),
          SetSpec(target: RepsTarget(reps: 4)),
          SetSpec(target: RepsTarget(reps: 4)),
        ],
        restSeconds: 150,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 1,
          everyWeeks: 2,
          cap: 10,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'k-kniebeuge',
        sets: [
          SetSpec(
            target: RepsTarget(reps: 5),
            load: Load(value: 45, unit: 'kg'),
          ),
          SetSpec(
            target: RepsTarget(reps: 5),
            load: Load(value: 45, unit: 'kg'),
          ),
        ],
        restSeconds: 120,
        progression: LinearProgression(
          field: ProgressionField.load,
          amount: 2.5,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'k-plank',
        sets: [SetSpec(target: DurationTarget(seconds: 60))],
        optional: true,
      ),
    ],
  ),
];

final _strengthProgram = Program(
  id: 'p-kraft-basis',
  name: 'Kraft Grundprogramm',
  domain: 'kraft',
  tags: const ['kraft', 'ganzkoerper'],
  description: 'Acht Wochen A/B-Rotation mit linearer Steigerung, dann Deload.',
  rationale:
      'Bewusst der klassische Fall, damit sichtbar wird: dieselbe Struktur, die '
      'den Geigenplan trägt, bildet auch ein normales Kraftprogramm ab — '
      'inklusive Gewichtssteigerung und Entlastungsphase.',
  phases: [
    Phase(
      id: 'k-ph-1',
      name: 'Aufbau',
      weeks: 6,
      goal: 'Kniebeuge 3×8 mit 55 kg.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'k-r-a'),
          DaySlot.rest(),
          const DaySlot(routineId: 'k-r-b'),
          DaySlot.rest(),
          const DaySlot(routineId: 'k-r-a'),
          DaySlot.rest(),
          DaySlot.rest(),
        ],
      ),
    ),
    Phase(
      id: 'k-ph-2',
      name: 'Deload',
      weeks: 2,
      description: 'Weniger Last, gleiche Bewegungen — Erholung ohne Pause.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'k-r-b'),
          DaySlot.rest(),
          const DaySlot(routineId: 'k-r-b'),
          DaySlot.rest(),
          DaySlot.rest(),
          DaySlot.rest(),
          DaySlot.rest(),
        ],
      ),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Zeichnen
// ---------------------------------------------------------------------------

final _artExercises = <Exercise>[
  const Exercise(
    id: 'z-gesten',
    name: 'Gestenzeichnen',
    domain: 'zeichnen',
    summary: 'Kurze Posen, jeweils 30 bis 60 Sekunden.',
    instructions: [
      'Timer auf 30 Sekunden.',
      'Nur die Bewegungslinie suchen, keine Kontur.',
      'Nicht korrigieren, nächste Pose.',
    ],
    benefits: ['Lockert die Hand.', 'Trainiert Sehen statt Symbolzeichnen.'],
    tags: ['grundlagen'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 600))],
  ),
  const Exercise(
    id: 'z-wertstudie',
    name: 'Wertstudie',
    domain: 'zeichnen',
    summary: 'Ein Motiv nur in drei Helligkeitsstufen.',
    instructions: [
      'Motiv wählen, Augen zusammenkneifen.',
      'Nur hell, mittel, dunkel anlegen.',
      'Keine Details, keine Linien.',
    ],
    benefits: ['Baut das Verständnis für Licht vor dem für Form.'],
    tags: ['grundlagen', 'licht'],
    defaultSets: [SetSpec(target: OpenTarget(prompt: 'eine Studie'))],
  ),
  const Exercise(
    id: 'z-perspektive',
    name: 'Perspektive konstruieren',
    domain: 'zeichnen',
    summary: 'Boxen im Raum mit Fluchtpunkten.',
    instructions: [
      'Horizont und zwei Fluchtpunkte setzen.',
      'Zehn Boxen konstruieren, verschiedene Höhen.',
      'Kanten sauber zu den Fluchtpunkten ziehen.',
    ],
    benefits: ['Macht Raum konstruierbar statt geschätzt.'],
    tags: ['konstruktion'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 900))],
  ),
];

final _artRoutines = <Routine>[
  const Routine(
    id: 'z-r-warmup',
    name: 'Warmlaufen + Studie',
    slots: [
      ExerciseSlot(
        exerciseId: 'z-gesten',
        sets: [SetSpec(target: DurationTarget(seconds: 600))],
        restSeconds: 60,
        progression: LinearProgression(
          field: ProgressionField.target,
          amount: 60,
          cap: 1200,
        ),
      ),
      ExerciseSlot(
        exerciseId: 'z-wertstudie',
        sets: [SetSpec(target: OpenTarget(prompt: 'eine Studie'))],
      ),
    ],
  ),
  const Routine(
    id: 'z-r-konstruktion',
    name: 'Konstruktionstag',
    slots: [
      ExerciseSlot(
        exerciseId: 'z-perspektive',
        sets: [SetSpec(target: DurationTarget(seconds: 900))],
        restSeconds: 60,
      ),
      ExerciseSlot(
        exerciseId: 'z-gesten',
        sets: [SetSpec(target: DurationTarget(seconds: 300))],
        optional: true,
      ),
    ],
  ),
];

final _artProgram = Program(
  id: 'p-zeichnen',
  name: 'Zeichnen Grundlagen',
  domain: 'zeichnen',
  tags: const ['zeichnen'],
  description: 'Sechs Wochen Grundlagen mit offenen Aufgaben.',
  rationale:
      'Der Beleg, dass auch unmessbare Übungen ins selbe Modell passen: eine '
      'Wertstudie hat kein Zielergebnis, nur ein Ergebnis. Der Player hakt sie '
      'ab, ohne eine Zahl zu erfinden.',
  phases: [
    Phase(
      id: 'z-ph-1',
      name: 'Sehen',
      weeks: 6,
      goal: 'Gestenzeichnen 20 Minuten am Stück ohne Korrigieren.',
      schedule: CycleSchedule(
        days: [
          const DaySlot(routineId: 'z-r-warmup'),
          const DaySlot(routineId: 'z-r-konstruktion'),
          const DaySlot(routineId: 'z-r-warmup'),
          DaySlot.rest(),
          const DaySlot(routineId: 'z-r-konstruktion'),
          const DaySlot(routineId: 'z-r-warmup'),
          DaySlot.rest(),
        ],
      ),
    ),
  ],
);
