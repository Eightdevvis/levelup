# LevelUp – Memory Index

Dieser Ordner ist die modulare Wissensbasis des Projekts. Jedes Thema hat
sein eigenes File. Nicht alles auf einmal lesen – über diesen Index
gezielt zu dem Thema springen, das gerade gebraucht wird.

Konvention: dieser Index enthält **nur** Thema → Pfad. Inhalte gehören
in die jeweiligen Files. Wenn ein neues Thema dazukommt → File anlegen
und hier eine Zeile ergänzen. Wenn ein Thema umbenannt/verschoben wird →
hier sofort mitziehen, sonst tote Links.

## Themen

Geschrieben:

| Thema                                   | Pfad                          |
|-----------------------------------------|-------------------------------|
| Projekt-Überblick & Status              | memory/ueberblick.md          |
| Wie ein Plan entsteht (Backend Rev. 2)  | memory/backend.md             |
| Was noch offen ist                      | `OFFEN.md` (Repo-Wurzel)      |
| Wie der Generator arbeiten soll         | `lernprogramm-generator-spec.md` (Repo-Wurzel) |

Vorgesehen, aber noch nicht geschrieben — hier stehen sie, damit klar ist,
dass sie fehlen, und nicht, damit jemand vergeblich klickt:

| Thema                                   | Pfad                          |
|-----------------------------------------|-------------------------------|
| Datenmodell (Programm → Phase → Einheit → Übung) | memory/datenmodell.md |
| App-Architektur (State, Store, Resolver)| memory/architektur.md         |
| Bildschirme & was jeder zeigt           | memory/screens.md             |
| Bildsprache & Lesbarkeit (E-Ink)        | memory/design.md              |
| Tests (was geprüft wird, welche Fallen) | memory/tests.md               |
| Bauen & Ausliefern (APK, Deploy)        | memory/bauen_ausliefern.md    |

Gestrichen: `uebungen.md`, `server.md`, `planbau.md`, `pool.md` — sie hätten
den Werkzeug-Agenten und den geteilten Pool beschrieben. Beides gibt es seit
Rev. 2 nicht mehr; was an ihre Stelle tritt, steht in `backend.md`.

`OFFEN.md` liegt bewusst außerhalb: es ist keine Doku des Ist-Zustands,
sondern eine Liste dessen, was fehlt – und soll beim Öffnen des Repos
sofort ins Auge fallen.

## Pflege

- Jede Doku-Änderung gehört in das passende Thema-File, nicht ins README.
- Wenn unklar wo etwas hingehört: lieber neues Thema-File anlegen als
  ein bestehendes überladen.
- README und CLAUDE.md verweisen auf diesen Index – sie selbst halten
  nur die Quick-Start-Kurzfassung.
- Wenn ein File etwas behauptet, das im Code nicht mehr stimmt: sofort
  korrigieren oder als **VERALTET** markieren. Eine falsche Doku ist
  teurer als gar keine, weil ihr geglaubt wird.
