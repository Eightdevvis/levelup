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
            name, description, benefits, cues, media, equipment, tags
            Die Tätigkeit ist kein eigenes Feld — sie steht als erster Tag

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

Der Hauptweg funktioniert ohne API-Key und ohne Kosten — **Plan aus dem
Chat**, in zwei Runden:

1. Das Vorhaben mit einer AI der Wahl besprechen.
2. Ersten Text kopieren: die AI stellt jede Übung als **Tag-Menge** dar.
   Wofür sie keinen Tag findet, schreibt sie selbst aus. Die App löst die
   Tag-Mengen gegen die eigene Bibliothek auf — eine Übung wird über ihre
   Tags erkannt, nicht über ihren Namen.
3. Zweiten Text kopieren: die AI ordnet die nun feststehenden Übungen zu
   Einheiten, Tagen und Phasen. Sie sieht dabei nur Kennungen, damit die
   Übungstexte nicht ein zweites Mal durch den Chat reisen.

Daneben bleibt der direkte Weg für ein fertiges Bundle: ein Prompt, ein JSON,
einfügen. Code-Zäune werden entfernt.

Ein Bundle transportiert Übungen, Listen und Programm zusammen, damit ein
generierter Plan seine Übungen mitbringt. Gleiche IDs werden ersetzt statt
gedoppelt — ein erneuter Import aktualisiert. Fehlende Verweise brechen den
Import nicht ab, sondern werden benannt und im Programm angezeigt.

Die Texte der zwei Runden werden in `lib/data/chat_prompts.dart` gebaut — sie
tragen den Tag-Pool bzw. die aufgelösten Übungen und sind deshalb nicht fest.
Der Prompt des direkten Weges liegt in `lib/data/ai_prompt.dart`.

Ein dritter Weg über einen eigenen Server (`server/`) ist gebaut, aber noch
nie gelaufen — siehe `OFFEN.md` #14.

## Enthaltene Inhalte

Keine. Wer die App installiert, findet eine leere Bibliothek und holt sich
seinen eigenen Plan — die vier früheren Beispielprogramme sind gelöscht,
nachdem eines beim echten Anschauen nicht taugte.

Zum Prüfen gibt es ein **Testprogramm** (`lib/data/demo_bundle.dart`), das
jede Funktion einmal zeigt: alle vier Zieltypen, Last, mehrere Sätze,
Steigerung, beide Tagespläne, Medien. Es wird über das Menü der
Übungsbibliothek geladen, nicht beim Start — und bleibt aus dem Tag-Pool des
Chat-Imports draußen.

Für Tests reicht `test/support/seed.dart` weiterhin Beispiele herein.

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
erscheinen als Verweis), es gibt keinen In-App-Editor für Programme, und der
eigene Server ist gebaut, aber nie gelaufen. Was sonst fehlt, steht in
`OFFEN.md`.
