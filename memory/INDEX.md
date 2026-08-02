# LevelUp – Memory Index

Dieser Ordner ist die modulare Wissensbasis des Projekts. Jedes Thema hat
sein eigenes File. Nicht alles auf einmal lesen – über diesen Index
gezielt zu dem Thema springen, das gerade gebraucht wird.

Konvention: dieser Index enthält **nur** Thema → Pfad. Inhalte gehören
in die jeweiligen Files. Wenn ein neues Thema dazukommt → File anlegen
und hier eine Zeile ergänzen. Wenn ein Thema umbenannt/verschoben wird →
hier sofort mitziehen, sonst tote Links.

## Themen

| Thema                                   | Pfad                          |
|-----------------------------------------|-------------------------------|
| Projekt-Überblick & Status              | memory/ueberblick.md          |
| Datenmodell (Programm → Phase → Einheit → Übung) | memory/datenmodell.md |
| Was eine Übung ist (Spec + Prüfer)      | memory/uebungen.md            |
| App-Architektur (State, Store, Resolver)| memory/architektur.md         |
| Bildschirme & was jeder zeigt           | memory/screens.md             |
| Server (Cloudflare Worker, D1, Endpunkte)| memory/server.md             |
| Planbau (Agent-Schleife, Modell, Recycling)| memory/planbau.md          |
| Der geteilte Pool (Suche, souverän/persönlich)| memory/pool.md           |
| Überarbeitung (Patch statt Neuschreiben)| memory/ueberarbeitung.md      |
| Bildsprache & Lesbarkeit (E-Ink)        | memory/design.md              |
| Tests (was geprüft wird, welche Fallen) | memory/tests.md               |
| Bauen & Ausliefern (APK, Deploy)        | memory/bauen_ausliefern.md    |
| Claude-spezifische Hinweise             | memory/claude_hinweise.md     |
| Was noch offen ist                      | `OFFEN.md` (Repo-Wurzel)      |

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
