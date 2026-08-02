// Testkulisse — KEIN Inhalt der App.
//
// Das waren einmal die mitgelieferten Beispielprogramme und zugleich die
// "offene Bibliothek" auf GitHub. Beides ist weg: die Übungen waren von Hand
// erfunden und teils unbrauchbar ("Notenkarten auf Zeit" setzte einen Stapel
// Notenkarten voraus, ohne zu sagen woher). Was hier steht, dient nur noch
// dazu, den Tests etwas zum Anfassen zu geben, und wird nirgends ausgeliefert.

import 'package:programs/model/exercise.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/program.dart';
import 'package:programs/model/progression.dart';
import 'package:programs/model/set_spec.dart';
import 'package:programs/model/target.dart';

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
    benefits: [
      'Verlagert das Lesen von Rechnen auf Erkennen.',
      'Baut die direkte Verbindung Notenbild → Griff, ohne Umweg über den Namen.',
    ],
    cues: ['Griff zuerst, Name danach.', 'Tempo vor Perfektion.'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 40, required: 30))],
    description: 'Einzelne Noten auf Karten so lange lesen, bis der Griff kommt, bevor der Name gedacht ist.\nKartenstapel im gewünschten Schlüssel mischen.\nKarte aufdecken, sofort den Griff auf dem Griffbrett zeigen.\nErst danach den Notennamen laut sagen — nicht umgekehrt.\nKarte auf "sitzt" oder "nochmal" legen, keine Pause zum Grübeln.',
    equipment: ['Notenkarten', 'Instrument'],
    tags: ['geige', 'notation', 'lesen'],
  ),
  const Exercise(
    id: 'v-rhythmus-klatschen',
    name: 'Rhythmus vom Blatt klatschen',
    benefits: [
      'Trennt das Rhythmusproblem vom Tonhöhenproblem.',
      'Macht komplexe Bach-Figuren lesbar, bevor das Instrument dazukommt.',
    ],
    cues: ['Laut zählen, immer.'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 300))],
    description: 'Rhythmen ohne Tonhöhe lesen — die halbe Notation, isoliert geübt.\nMetronom auf ein ruhiges Tempo stellen.\nTakt anschauen, einmal still mitzählen.\nRhythmus klatschen und dabei laut zählen.\nBei Fehler nicht anhalten — im nächsten Takt wieder einsteigen.',
    equipment: ['Metronom', 'Notenmaterial'],
    tags: ['geige', 'notation', 'rhythmus'],
  ),
  const Exercise(
    id: 'v-vom-blatt-singen',
    name: 'Vom Blatt singen',
    benefits: [
      'Baut das innere Gehör für das, was auf dem Papier steht.',
      'Deckt auf, welche Stellen nur motorisch, nicht verstanden sind.',
    ],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 300))],
    description: 'Die Melodie singen, bevor sie gespielt wird — zwingt zur inneren Vorstellung statt zum Abgreifen.\nGrundton am Instrument anspielen, dann Instrument weglegen.\nMelodie langsam singen, Finger dürfen mitzeigen.\nAn unsicheren Stellen anhalten und das Intervall benennen.',
    tags: ['geige', 'notation', 'gehoer'],
  ),
  const Exercise(
    id: 'v-tonleiter-metronom',
    name: 'Tonleitern mit Metronom',
    benefits: [
      'Verbindet Tonartwissen mit der Hand statt nur mit dem Kopf.',
      'Gibt der Übung eine harte Zahl, an der Fortschritt sichtbar wird.',
    ],
    cues: ['Vorzeichen laut sagen.'],
    defaultSets: [
      SetSpec(
        target: DurationTarget(seconds: 480),
        load: Load(value: 60, unit: 'bpm'),
      ),
    ],
    description: 'Tonleitern in wechselnden Tonarten, Tempo als messbare Größe.\nTonart des Tages wählen, Vorzeichen laut benennen.\nZwei Oktaven auf und ab, gebundene Viertel.\nTempo erst erhöhen, wenn drei Durchgänge sauber sind.',
    equipment: ['Metronom'],
    tags: ['geige', 'technik', 'tonarten'],
  ),
  const Exercise(
    id: 'v-tonarten-theorie',
    name: 'Tonarten und Quintenzirkel',
    benefits: [
      'Verwandelt zufällige Vorzeichen in erwartbare Muster.',
      'Reduziert die Menge, die beim Lesen gemerkt werden muss.',
    ],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 600))],
    description: 'Vorzeichen, Stufen und Verwandtschaften — das Gerüst, an dem Notation erst Bedeutung bekommt.\nTonart des Tages: Vorzeichen aus dem Kopf aufschreiben.\nStufendreiklänge notieren und benennen.\nParallele und Dominanttonart dazu bestimmen.',
    tags: ['geige', 'theorie'],
  ),
  const Exercise(
    id: 'v-intervalle-griffbrett',
    name: 'Intervalle auf dem Griffbrett',
    benefits: [
      'Macht aus Einzelnoten Beziehungen — die Einheit, in der man wirklich liest.',
    ],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 24, required: 18))],
    description: 'Notiertes Intervall sehen, sofort greifen.\nZwei Noten aufdecken.\nIntervall benennen und direkt greifen.\nDann spielen und gegen die Vorstellung prüfen.',
    tags: ['geige', 'notation', 'technik'],
  ),
  const Exercise(
    id: 'v-bach-analyse',
    name: 'Bach-Takt analysieren',
    benefits: [
      'Bach wird lesbar als Struktur statt als Notenwand.',
      'Was analysiert ist, muss nicht auswendig gelernt werden.',
    ],
    defaultSets: [SetSpec(target: OpenTarget(prompt: 'ein Takt, schriftlich'))],
    description: 'Einen einzelnen Takt schriftlich auseinandernehmen, ohne ihn zu spielen.\nEinen Takt abschreiben.\nHarmonische Funktion und Stufe eintragen.\nMotiv markieren und benennen, wo es wiederkehrt.',
    equipment: ['Notenpapier', 'Bleistift'],
    tags: ['geige', 'theorie', 'bach'],
  ),
  const Exercise(
    id: 'v-bach-vomblatt',
    name: 'Bach vom Blatt, halbes Tempo',
    benefits: [
      'Trainiert genau das Lesen, nicht das Auswendigkönnen.',
      'Hält den Blick vorne statt an der Fehlerstelle.',
    ],
    cues: ['Nicht anhalten.', 'Blick eine Note voraus.'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 900))],
    description: 'Unbekannte Takte im Zeitlupentempo lesen, ohne vorher zu üben.\nVier neue Takte auswählen, nicht vorher anschauen.\nMetronom auf halbes Zieltempo.\nDurchspielen ohne anzuhalten, Fehler stehen lassen.\nDanach erst zurückgehen und die Stelle klären.',
    tags: ['geige', 'bach', 'lesen'],
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
    benefits: ['Grundlage für Melodiediktat und Vom-Blatt-Singen.'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 20, required: 14))],
    description: 'Zwei Töne, Intervall benennen — die Grundeinheit des Hörens.\nIntervall abspielen lassen, nur einmal.\nBenennen, bevor nachgedacht wird.\nErst danach kontrollieren und ggf. nachsingen.',
    tags: ['gehoerbildung', 'gehoer'],
  ),
  const Exercise(
    id: 'g-akkorde',
    name: 'Akkordqualität hören',
    benefits: ['Macht Harmonik hörbar statt nur lesbar.'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 16, required: 11))],
    description: 'Dur, Moll, vermindert, übermäßig unterscheiden.\nAkkord abspielen.\nQualität benennen.\nBei Unsicherheit Terz herausgreifen und singen.',
    tags: ['gehoerbildung', 'gehoer', 'harmonik'],
  ),
  const Exercise(
    id: 'g-melodiediktat',
    name: 'Melodiediktat',
    benefits: ['Verbindet Gehör und Notation in beide Richtungen.'],
    defaultSets: [SetSpec(target: QuotaTarget(attempts: 8, required: 5))],
    description: 'Kurze Melodie hören und notieren.\nMelodie zweimal hören.\nRhythmus zuerst notieren, dann Tonhöhen.\nGegen die Vorlage prüfen.',
    tags: ['gehoerbildung', 'gehoer', 'notation'],
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
    benefits: ['Baut Beinkraft.', 'Überträgt auf fast jede andere Bewegung.'],
    cues: ['Brust hoch.', 'Ferse bleibt am Boden.'],
    defaultSets: [
      SetSpec(
        target: RepsTarget(reps: 8),
        load: Load(value: 40, unit: 'kg'),
      ),
    ],
    description: 'Grundübung für Beine und Rumpf.\nStand etwa schulterbreit, Zehen leicht nach außen.\nHüfte zurück und runter, Knie folgen der Fußrichtung.\nBis mindestens parallel, dann kontrolliert hoch.',
    equipment: ['Langhantel'],
    tags: ['kraft', 'unterkoerper'],
  ),
  const Exercise(
    id: 'k-klimmzug',
    name: 'Klimmzug',
    benefits: ['Rücken und Griffkraft.'],
    defaultSets: [SetSpec(target: RepsTarget(reps: 5))],
    description: 'Zug nach oben aus dem Hang.\nGriff etwas breiter als schulterbreit.\nSchulterblätter zuerst nach unten ziehen.\nHochziehen bis Kinn über der Stange, kontrolliert ablassen.',
    equipment: ['Klimmzugstange'],
    tags: ['kraft', 'oberkoerper'],
  ),
  const Exercise(
    id: 'k-liegestuetz',
    name: 'Liegestütz',
    benefits: ['Brust, Trizeps, Rumpfspannung.'],
    defaultSets: [SetSpec(target: RepsTarget(reps: 12))],
    description: 'Druckbewegung ohne Geräte.\nHände unter den Schultern, Körper auf einer Linie.\nEllbogen etwa 45 Grad zum Körper.\nBrust bis knapp über den Boden.',
    tags: ['kraft', 'oberkoerper'],
  ),
  const Exercise(
    id: 'k-plank',
    name: 'Unterarmstütz',
    benefits: ['Stabiler Rumpf.'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 45))],
    description: 'Statische Rumpfspannung.\nUnterarme unter den Schultern.\nBecken leicht kippen, Gesäß anspannen.\nHalten, ruhig weiteratmen.',
    tags: ['kraft', 'rumpf'],
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
    benefits: ['Lockert die Hand.', 'Trainiert Sehen statt Symbolzeichnen.'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 600))],
    description: 'Kurze Posen, jeweils 30 bis 60 Sekunden.\nTimer auf 30 Sekunden.\nNur die Bewegungslinie suchen, keine Kontur.\nNicht korrigieren, nächste Pose.',
    tags: ['zeichnen', 'grundlagen'],
  ),
  const Exercise(
    id: 'z-wertstudie',
    name: 'Wertstudie',
    benefits: ['Baut das Verständnis für Licht vor dem für Form.'],
    defaultSets: [SetSpec(target: OpenTarget(prompt: 'eine Studie'))],
    description: 'Ein Motiv nur in drei Helligkeitsstufen.\nMotiv wählen, Augen zusammenkneifen.\nNur hell, mittel, dunkel anlegen.\nKeine Details, keine Linien.',
    tags: ['zeichnen', 'grundlagen', 'licht'],
  ),
  const Exercise(
    id: 'z-perspektive',
    name: 'Perspektive konstruieren',
    benefits: ['Macht Raum konstruierbar statt geschätzt.'],
    defaultSets: [SetSpec(target: DurationTarget(seconds: 900))],
    description: 'Boxen im Raum mit Fluchtpunkten.\nHorizont und zwei Fluchtpunkte setzen.\nZehn Boxen konstruieren, verschiedene Höhen.\nKanten sauber zu den Fluchtpunkten ziehen.',
    tags: ['zeichnen', 'konstruktion'],
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
