# Projekt-Überblick & Status

## Was LevelUp ist

Eine Handy-App für strukturierte Übungsprogramme – egal welcher Disziplin.
Die Struktur einer Workout-App (Programm wählen, Übersicht sehen, eine Übung
nach der nächsten fokussiert abspielen), aber ohne die Annahme, dass es um
Fitness geht. Ein Geigenplan, ein Gehörtrainingsplan, ein Zeichenplan und ein
Kraftprogramm laufen durch exakt dieselben Objekte.

**Der Paketname ist `programs`, nicht `levelup`.** Imports heißen
`package:programs/...`. Der Produktname wurde später geändert, der Paketname
nicht. Das ist die häufigste Stolperfalle beim Schreiben neuer Tests.

## Der Gedanke dahinter (Bach-Beispiel)

Wer gut Geige spielt, aber Bach nicht vom Blatt bekommt, hat kein Bach-Problem,
sondern ein Notationsproblem. Mehr Bach üben hilft nicht. Die AI soll deshalb
**die Ursache diagnostizieren, nicht das Symptom bedienen** – im Bach-Plan
kommt in den ersten vier Wochen kein Bach vor.

Das ist die Messlatte für jede Änderung am Planbau: Wird der Plan dadurch
persönlicher und ursachengerechter, oder nur schneller/billiger?

## Warum es die App überhaupt gibt

Die Recherche ergab zwei Lager und nichts dazwischen:

- **Struktur ohne Offenheit** – Boostcamp, Hevy, Everfit: Periodisierung,
  Übungsbibliothek, Progression, alles fest auf Fitness verdrahtet.
- **Offenheit ohne Inhalt** – Routinery, Tiimo, Structured: beliebige Domänen,
  aber ein Schritt ist nur *Name + Dauer*. Kein Übungsobjekt, keine
  wiederverwendbare Bibliothek, keine Progression über Wochen.

Das offene Lager blieb inhaltsleer wegen des Henne-Ei-Problems: eine
domänenübergreifende Übungsdatenbank ist unendlich groß und daher nie fertig.
LevelUp dreht das um – **die AI erzeugt die Übungsobjekte beim Planbau mit, die
Bibliothek ist Ergebnis statt Voraussetzung** (siehe `pool.md`).

## Aktueller Stand (2026-08-02)

Das Backend ist gerade nach `lernprogramm-generator-spec.md` (Rev. 2) neu
gebaut. Was davor stand — ein Werkzeug-Agent, der selbst entschied, wann er
sucht und wann er schreibt — ist weg; siehe `backend.md`.

| Komponente                                   | Stand                                  |
|----------------------------------------------|----------------------------------------|
| Datenmodell, Resolver, Persistenz            | fertig + getestet                      |
| Alle Bildschirme inkl. Player                | fertig, nach Fitness-App-Vorbild umgebaut |
| Import per Kopieren/Einfügen (kostenlos)     | fertig                                 |
| Pipeline Diagnose → Architekt → Kurator      | gebaut, 111 Tests grün, **noch nie echt gelaufen** |
| Vier Eingabefelder + Rückfragerunde in der App| gebaut, 119 Tests grün                |
| Überarbeitung als Patch                      | live – gemessen 10 s gegen 3:46 für eine Neuerzeugung |
| Offene Bibliothek über das Netz              | live, liest die Programmliste          |
| Grundstock (12 Geige, 12 Krafttraining)      | geschrieben, **nicht eingespielt** – `OFFEN.md` #15 |
| Vectorize-Indizes, `schema_v3.sql` entfernt  | **nicht angelegt** – `OFFEN.md` #15    |
| Cloudflare-Plan (Free vs. Paid)              | **ungeklärt** – `OFFEN.md` #14         |
| Missbrauchsschutz (Geräte-Registrierung)     | **fehlt** – `OFFEN.md` #1, das teuerste Loch |
| Bezahlung, Konten                            | nicht angefangen                       |
| Veröffentlichung in den Stores               | nicht angefangen                       |

**Nichts davon ist gegen die echte API gelaufen.** Der Sandkasten dieses
Umbaus hatte kein Netz zu Anthropic und keine Vectorize-Indizes; alle Zahlen
oben sind Tests mit konservierten Antworten, keine Messungen.

## Handgeschriebene Inhalte gibt es nicht mehr

Früher lagen vier Beispielprogramme (Bach, Gehörtraining, Kraft, Zeichnen) als
Seed im Repo. Sie sind **gelöscht** – auf Ansage, nachdem eines davon beim
echten Anschauen nicht taugte („Notenkarten auf Zeit"). Es gibt keinen Seed
mehr, keine `data/seed.dart`, und `library/index.json` ist ein leerer Rest.
Wer die App installiert, findet eine leere Bibliothek und holt sich seinen
eigenen Plan.

Für Tests wird bewusst weiterhin ein Beispiel-Bundle hereingereicht –
`test/support/seed.dart`, nicht `lib/`.

## Verwandt

- Was als Nächstes fehlt: `OFFEN.md` in der Wurzel
- Wie der Plan entsteht: `backend.md`
- Die verbindliche Fassung: `lernprogramm-generator-spec.md` in der Wurzel
