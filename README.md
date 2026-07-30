# Programs

Eine Handy-App für strukturierte Übungsprogramme — egal welcher Disziplin.

Die Struktur einer Workout-App (Programm auswählen, Übersicht sehen, eine Übung
nach der nächsten fokussiert abspielen), aber ohne die Annahme, dass es um
Fitness geht. Ein Geigenplan, ein Gehörtrainingsplan, ein Zeichenplan und ein
Kraftprogramm laufen durch exakt dieselben Objekte.

## Warum

Die Recherche zum Thema ergab zwei getrennte Lager und nichts dazwischen:

- **Struktur ohne Offenheit** — Boostcamp, Hevy, Everfit: mehrwöchige
  Periodisierung, Übungsbibliothek, Progression. Alles fest auf Fitness verdrahtet.
- **Offenheit ohne Inhalt** — Routinery, Tiimo, Structured: beliebige Domänen,
  aber ein Schritt ist nur *Name + Dauer*. Kein Übungsobjekt, keine
  wiederverwendbare Bibliothek, keine Progression über Wochen.

AI-Planimport gibt es (HevyGPT), aber fitness-beschränkt und auf vier Routinen
gedeckelt.

Der Grund, warum das offene Lager inhaltsleer geblieben ist, war das
Henne-Ei-Problem: eine domänenübergreifende Übungsdatenbank ist unendlich groß
und daher nie fertig. Diese App dreht das um — die AI erzeugt die Übungsobjekte
beim Planbau mit, die Bibliothek ist Ergebnis statt Voraussetzung.

## Datenmodell

Vier Ebenen, alle in `lib/model/`:

```
Exercise    das wiederverwendbare Übungsobjekt
            Name, Anleitung, Vorteile, Merksätze, Medien, Voraussetzungen
            `domain` ist ein freies Tag, kein Enum

Routine     die "Liste" — geordnete Folge von ExerciseSlots
            Slot = Übung + Sätze + Pause + Progression

Phase       Abschnitt mit eigener Länge und eigenem Schedule
            Schedule = everyDay (eine Liste, jeden Tag)
                     | cycle   (n Tage im Wechsel, inkl. Pausentagen)

Program     Folge von Phasen
            plus `rationale` — warum der Plan so aussieht
```

### Die zwei Entscheidungen, an denen alles hängt

**1. Ausführungstyp am Ziel, nicht an der App.** Ein `Target` ist eines von:

| Typ        | Beispiel                          | Wofür                         |
|------------|-----------------------------------|-------------------------------|
| `duration` | 10 min Tonleitern                 | zeitbasiertes Üben            |
| `reps`     | 12 Wiederholungen                 | Training, Takte, Durchgänge   |
| `quota`    | 16 von 20 Intervallen richtig     | Gehör, Vokabeln, Notenlesen   |
| `open`     | eine Skizze                       | kreative Aufgaben ohne Zahl   |

Ohne `quota` und `open` wäre es unweigerlich doch eine Fitness-App geworden.

**2. Progression pro Phase, nicht pro Programm.** `weekInPhase` ist der Wert, an
dem gesteigert wird — beim Phasenwechsel beginnt die Rampe neu. Drei Regeln:

- `none` — jede Woche gleich
- `linear` — `+2 Wdh./Woche`, `+4 bpm alle 2 Wochen`, mit Deckel
- `table` — explizite Werte je Woche, inklusive Deload

`linear` wirkt wahlweise auf das Ziel oder auf die `load` (kg, bpm, %). Deshalb
ist die Last numerisch mit Einheit statt Freitext — sonst wäre
"jede Woche 4 bpm schneller" nicht ausdrückbar.

## AI-Anbindung

Der Weg funktioniert heute ohne API-Key und ohne Kosten:

1. Im Import-Screen **Prompt kopieren** — enthält das vollständige Schema und
   die Anweisung, zuerst das eigentliche Problem zu diagnostizieren.
2. In Claude einfügen, dahinter das eigene Anliegen beschreiben.
3. Antwort-JSON zurück in die App einfügen. Code-Zäune werden entfernt.

Ein Bundle transportiert Übungen, Listen und Programm zusammen, damit ein
generierter Plan seine Übungen mitbringt. Gleiche IDs werden ersetzt statt
gedoppelt — ein erneuter Import aktualisiert. Fehlende Verweise brechen den
Import nicht ab, sondern werden benannt und im Programm angezeigt.

Der Prompt liegt in `lib/data/ai_prompt.dart`. Ein späterer direkter API-Aufruf
kann dieselbe Vorlage benutzen.

## Enthaltene Beispielprogramme

Vier Domänen, um zu zeigen, dass die Struktur trägt:

- **Bach lesen lernen** (Geige, 12 Wochen) — der Fall, an dem das Modell
  entworfen wurde. Diagnose: das Problem ist nicht zu wenig Bach, sondern das
  Notationsverständnis. Die ersten vier Wochen enthalten deshalb keinen Bach.
- **Gehörtraining Grundstock** (8 Wochen) — Quotenziele mit langsam steigender Hürde.
- **Kraft Grundprogramm** (8 Wochen) — A/B-Rotation, Gewichtssteigerung, Deload-Phase.
- **Zeichnen Grundlagen** (6 Wochen) — offene Aufgaben ohne Zielwert.

## Aufbau

```
lib/
  model/      Exercise, Routine, Program, Target, Progression, Session, Library
  engine/     resolver.dart — Programm + Tag → aufgelöste Session
  data/       storage.dart (JSON, atomar), seed.dart, ai_prompt.dart
  state/      app_state.dart — ein ChangeNotifier, kein State-Management-Paket
  ui/         home, program, day, player, exercise, library, import
test/         progression, resolver, import/persistenz, Widget-Durchläufe
```

Der Resolver ist die Stelle, an der die Ebenen zusammenkommen: die Phase
bestimmt den Schedule, die Woche die Progression, der Tag die Liste.

## Entwicklung

```bash
flutter test            # 58 Tests
flutter analyze
flutter run -d linux    # Desktop
```

### Android

Das Android SDK ist vorhanden, es fehlt nur ein JDK:

```bash
sudo apt install openjdk-17-jdk
flutter build apk --debug
```

## Stand

Fertig und getestet: Datenmodell, Resolver, Persistenz, Import/Export,
alle Screens inklusive Player mit allen vier Übungstypen.

Noch offen: Medien werden nur als lokale Datei oder Asset angezeigt (Remote-URLs
erscheinen als Verweis), es gibt keinen In-App-Editor für Programme, und die
AI-Anbindung läuft über Kopieren/Einfügen statt über einen direkten API-Aufruf.
