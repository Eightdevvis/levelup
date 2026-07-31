# Was noch offen ist

Stand: 31.07.2026, nach dem Ausrollen von Pool und Einspruch.

Sortiert danach, wann es weh tut — nicht danach, wie viel Arbeit es ist.

---

## Bevor die App öffentlich wird

### 1. Jeder kann sich unbegrenzt Geräte anlegen

`POST /v1/devices` verlangt nichts und begrenzt nichts. Jeder Aufruf gibt ein
frisches Token mit vollem Freikontingent. Wer das in eine Schleife steckt, holt
sich beliebig viele Gratispläne — bezahlt aus dem Anthropic-Guthaben des
Betreibers.

Das Tageslimit greift **pro Gerät**, nicht pro Mensch, und ist deshalb hier
wirkungslos.

Das ist das teuerste offene Loch. Mögliche Antworten, von einfach nach gründlich:
eine Sperre pro IP und Tag; ein Gesamtdeckel für neue Geräte pro Stunde; ein
Nachweis beim ersten Aufruf (Turnstile); oder erst dann Freikontingent, wenn ein
App-Store-Kaufbeleg vorliegt. Das Erste ist in einer Stunde gebaut und deckt 95 %
der Fälle.

### 2. Jeder kann in den geteilten Pool schreiben

`POST /v1/plans/accept` nimmt jedes Bundle an, das nach einem Plan aussieht. Es
gibt keinen Nachweis, dass der Plan aus einem eigenen Lauf stammt. Wer will,
kippt Unsinn in die Bibliothek, aus der dann alle anderen schöpfen.

Abgefedert ist es nur halb: jede Zeile trägt ihre `device_id`, eine schlechte
Quelle lässt sich also finden und ausräumen. Das ist Aufräumen im Nachhinein,
keine Verhinderung.

Der saubere Weg: beim Erzeugen einen Fingerabdruck des Plans mitschreiben und
beim Annehmen verlangen. Haken dabei — nach einer Überarbeitung stimmt der
Fingerabdruck nicht mehr, weil der Patch auf dem Gerät angewendet wird. Also
entweder der Server wendet ihn zum Mitschreiben ebenfalls an, oder es reicht ein
loserer Nachweis (dieses Gerät hatte in den letzten 24 Stunden einen
erfolgreichen Lauf).

### 3. Datenschutz

Wer den Server betreibt, ist Verantwortlicher im Sinne der DSGVO. Offen:

- Datenschutzerklärung, in der App erreichbar
- Auftragsverarbeitungsverträge mit Anthropic und Cloudflare
- Eine Antwort darauf, wie lange Zeilen in `generations` liegen bleiben
- Ein Weg, ein Gerät und seine Daten zu löschen. Es gibt derzeit **keinen**
  Endpunkt dafür. Das Gerätetoken ist ein Pseudonym, damit personenbezogen.
- Der Pool enthält von Nutzern beigesteuerte Inhalte. Auch wenn der persönliche
  Teil entfernt wird: die Frage, ob jemand seinen Beitrag zurückziehen kann,
  gehört beantwortet, bevor sie gestellt wird.

### 4. Zwei Bibliotheken, die nichts voneinander wissen

`lib/data/open_library.dart` lädt weiter einen statischen Katalog von
GitHub raw. Der Server hat inzwischen einen eigenen, lebenden Pool
(`pool_exercises`, `pool_programs`). Zwei „offene Bibliotheken", die
auseinanderlaufen — der Knopf in der App zeigt nicht das, woraus die AI schöpft.

Zu entscheiden: entweder der Knopf liest künftig den Server-Pool (dann braucht
es einen Lese-Endpunkt), oder der GitHub-Katalog fliegt raus. Das Erste ist
richtig, weil der Pool durch Nutzung wächst und der Katalog nicht.

---

## Sobald es Geld kostet

### 5. Bezahlung

Verteilt wird über Play Store und App Store. Beide verlangen für digitale Güter
ihre eigene Abrechnung, 15–30 %. Also **Google Play Billing und StoreKit**, kein
Stripe. Zu bauen: Belegprüfung im Worker, ein Guthabenkonto pro Gerät, und die
Umstellung von „Freikontingent" auf „Freikontingent plus gekauftes Guthaben".

### 6. Konten

`devices.user_id` steht leer und ist genau dafür da. Was fehlt, ist der ganze
Weg: Anmeldung, ein Gerät an ein Konto knüpfen, mehrere Geräte an dasselbe
Konto, Guthaben teilen. Wichtig wird das in dem Moment, in dem jemand ein neues
Handy hat — heute wäre sein gekauftes Guthaben weg.

### 7. Das Verhältnis Überarbeitung zu Erzeugung

Eine Überarbeitung zählt wie eine Erzeugung, kostet aber nur einen Bruchteil:
gemessen 10 Sekunden gegen 3:46, ein paar hundert Ausgabe-Token gegen 14.000.
Das war die richtige Entscheidung, solange nicht klar war, wie teuer ein Patch
wirklich ist. Jetzt ist es klar, und das Verhältnis darf schief heißen.

Zu ändern wäre es billig — `generations.kind` unterscheidet schon zwischen
`plan` und `revision`, die Zählung in `quotaFor()` müsste sie nur gewichten.

---

## Irgendwann

### 8. Der Pool wird nie aufgeräumt

Es gibt kein Entfernen, keine Qualitätsschwelle, keine Zusammenführung von
Dubletten. `used_count` sortiert die Suche, mehr passiert damit nicht. Bei
zweistelligen Zahlen egal, bei vierstelligen nicht.

### 9. Kennungen können kollidieren

Die App führt Übungen per `id` zusammen. Übernimmt jemand einen Plan aus dem
Pool, der eine `id` benutzt, die er selbst schon anders belegt hat, wird seine
eigene Fassung überschrieben. Der Domänen-Präfix im Prompt
(`geige-rhythmus-klopfen`) macht es unwahrscheinlich, aber nicht unmöglich.

Sauber wäre, beim Zusammenführen zu erkennen, dass zwei Übungen mit gleicher
Kennung verschieden sind, und die hereinkommende umzubenennen.

### 10. Die Suche ist absichtlich dumm

Stichwörter gegen ein Textfeld, Treffer gezählt. Kein FTS5, keine Vektoren — der
semantische Teil sitzt im Modell, das die Wörter formuliert und die Treffer
beurteilt. Das funktioniert nachweislich (vier Suchläufe, deutsch und englisch
gemischt, 12 von 14 Bausteinen gefunden). Bei fünfstelligem Pool ist
`src/pool.ts` die Stelle zum Austauschen; die Schnittstelle bleibt.

### 10b. Die Übungsprüfung hat keinen automatischen Test

`server/src/exercise_spec.ts` prüft jede erzeugte Übung und löst bei Verstößen
eine Korrekturrunde aus — sie entscheidet also mit, was in den Pool kommt. Für
den Worker gibt es aber kein Testgerüst; geprüft wurde von Hand gegen einen
echten Plan (0 Beanstandungen) und gegen ein absichtlich schlechtes Bundle (5
richtige). Das gehört in einen Test, sobald der Worker eins bekommt.

Beim Bauen ist übrigens genau der Fehler passiert, vor dem die Prüfung schützen
soll: die erste Fassung verglich `requirements` mit dem Text und meldete bei
einem echten Plan 25 Beanstandungen, darunter "Tastatur" bei einer Tipp-Übung.
Ein Prüfer mit überwiegend Fehlalarmen ist schlechter als keiner. Die Prüfung
deckt jetzt nur noch Eindeutiges ab; Material bleibt reine Prompt-Regel.

### 11. Zwei Prompts, die auseinanderlaufen können

`server/src/plan_prompt.ts` ist der verbindliche. `lib/data/ai_prompt.dart` ist
die Fassung für Kopieren und Einfügen und kennt weder Werkzeuge noch Pool. Das
ist so gewollt, aber das Schema darin muss mitwandern, wenn sich das Datenmodell
ändert. Es gibt nichts, das das prüft.

### 12. Was passiert, wenn die AI aufgibt

`MAX_TURNS` steht auf 8. Wird es erreicht, fliegt ein `UpstreamError` und der
Nutzer liest „Der Planer ist gerade nicht erreichbar" — was nicht stimmt. Der
Fall ist unwahrscheinlich (gemessen: 6 Züge für einen gründlichen Lauf), aber
die Meldung wäre irreführend.

### 13. Veröffentlichen

Entwicklerkonten bei Google und Apple, Signierung, Store-Einträge, Screenshots,
Altersfreigabe. Nichts davon ist angefangen.
