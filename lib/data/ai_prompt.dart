/// Der Prompt, den man in Claude (oder ein anderes Modell) kippt, um einen
/// Plan zu bekommen, den die App direkt lesen kann.
///
/// Bewusst als Text und nicht als API-Aufruf: so funktioniert die AI-Funktion
/// sofort, ohne Schlüssel, ohne Kosten und mit dem Modell, mit dem man ohnehin
/// schon redet. Der API-Weg kann später dieselbe Vorlage benutzen.
const String kAiPromptTemplate = r'''
Du baust einen Übungsplan für meine App "Programs". Antworte mit GENAU EINEM
JSON-Objekt, ohne Text davor oder danach.

Wichtig zur Herangehensweise: diagnostiziere zuerst das eigentliche Problem,
bevor du Übungen aneinanderreihst. Wenn jemand sein Ziel nicht erreicht, liegt
das oft eine Ebene tiefer als gedacht — dann gehört diese tiefere Ebene an den
Anfang des Plans. Schreib diese Überlegung in das Feld "rationale".

SCHEMA

{
  "version": 1,
  "exercises": [ Exercise, ... ],
  "routines":  [ Routine, ... ],
  "programs":  [ Program, ... ]
}

Exercise = {
  "id": "kurz-kebab-case",         // eindeutig, wird referenziert
  "name": "Anzeigename",
  "domain": "geige",               // freies Tag, z.B. kraft, zeichnen, sprache
  "summary": "ein bis zwei Sätze",
  "instructions": ["Schritt 1", "Schritt 2"],
  "benefits": ["wofür das gut ist"],
  "cues": ["kurzer Merksatz"],     // wird während der Ausführung eingeblendet
  "requirements": ["Metronom"],
  "tags": ["notation"],
  "defaultSets": [SetSpec]         // optional
}

Routine = {                        // eine Liste von Übungen, die am Stück läuft
  "id": "kebab-case",
  "name": "Anzeigename",
  "description": "optional",
  "slots": [{
    "exerciseId": "verweis-auf-exercise-id",
    "sets": [SetSpec],
    "restSeconds": 60,             // optional
    "note": "optionaler Hinweis",
    "optional": false,             // true = darf ausgelassen werden
    "progression": Progression     // optional
  }]
}

SetSpec = {
  "target": Target,
  "load": {"value": 60, "unit": "bpm"},   // optional, z.B. kg, bpm, %
  "note": "optional"
}

Target = eines von:
  {"kind": "duration", "seconds": 600}                    // zeitbasiert
  {"kind": "reps", "reps": 12}                            // Wiederholungen
  {"kind": "quota", "attempts": 20, "required": 16}       // Trefferquote
  {"kind": "open", "prompt": "eine Skizze"}               // ohne Zielwert

Wähle den Typ, der wirklich passt. Gehörtraining und Vokabeln sind "quota",
nicht "duration". Kreative Aufgaben sind "open" — erfinde keine Zahl.

Progression = eines von:
  {"kind": "none"}
  {"kind": "linear", "field": "target"|"load", "amount": 2,
   "everyWeeks": 1, "cap": 38}    // steigert pro Woche innerhalb der Phase
  {"kind": "table", "perWeek": [SetSpec oder null, ...]}  // explizit je Woche

Bei "quota" steigert "field": "target" die nötigen Treffer, nicht die Versuche.

Program = {
  "id": "kebab-case",
  "name": "Anzeigename",
  "description": "ein bis zwei Sätze",
  "domain": "geige",
  "tags": ["notation"],
  "rationale": "Warum der Plan so aussieht — die Diagnose.",
  "phases": [{
    "id": "kebab-case",
    "name": "Phasenname",
    "weeks": 4,
    "description": "optional",
    "goal": "woran man merkt, dass die Phase sitzt",
    "schedule": Schedule
  }]
}

Schedule = eines von:
  {"kind": "everyDay", "routineId": "x", "daysPerWeek": 6}
      // jeden Tag dieselbe Liste
  {"kind": "cycle", "days": [{"routineId": "a"}, {"label": "Pause"}, ...]}
      // wiederkehrender Zyklus; ein Eintrag ohne routineId ist ein Pausentag

Die Länge von "days" bestimmt, wie viele Tage eine Woche dieses Programms hat.
Für einen normalen Wochenplan nimm 7 Einträge inklusive Pausentagen.

REGELN
- Jede in "slots" referenzierte exerciseId muss in "exercises" vorkommen.
- Jede in einem Schedule referenzierte routineId muss in "routines" vorkommen.
- Nutze mehrere Phasen, wenn sich der Charakter des Trainings ändert.
- Gib Übungen echte instructions und benefits, keine Platzhalter.
- Nur JSON ausgeben, keine Erklärung drumherum.

MEIN ANLIEGEN:
''';
