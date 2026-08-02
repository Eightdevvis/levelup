# Wie ein Plan entsteht (Backend, Rev. 2)

Die verbindliche Fassung ist `lernprogramm-generator-spec.md` in der Wurzel.
Hier steht nur, was man wissen muss, bevor man den Code aufmacht — und warum
er so aussieht.

## Was vorher stand und warum es weg ist

Bis Ende Juli führte ein einziger Aufruf ein Gespräch mit Werkzeugen: das
Modell entschied selbst, wann es in der Bibliothek sucht und wann es schreibt.
Das war die Stelle, an der die Wiederverwendung unzuverlässig wurde — bequemer
ist es immer, neu zu erfinden. `agent.ts`, `plan_prompt.ts` und
`exercise_spec.ts` sind gelöscht.

Jetzt hat jeder KI-Aufruf genau eine Aufgabe und ein festes Ausgabeformat.
**Gesucht wird im Code, nicht vom Modell.**

## Die Kette

```
[1]  Diagnose            KI    → Problemmodell           prompts/diagnose.ts
[1b] Rückfragen          KI    → dasselbe, korrigiert    (nur wenn nötig)
[2]  Architekt           KI    → Phasen/Einheiten/Bedarfe prompts/architekt.ts
[3]  Bedarfe eindampfen  CODE  → eindeutige Bedarfsliste  bedarfe.ts
[3b] Retrieval           CODE  → Kandidaten               retrieval.ts
[4]  Kurator             KI    → wiederverwenden/erzeugen prompts/kurator.ts
[5]  Dedupe & Save       CODE  → in die Bibliothek        speichern.ts
```

`pipeline.ts` führt [3] bis [5] aus, `bundle.ts` übersetzt am Ende ins Format
der App, `index.ts` hängt das an die Endpunkte.

## Die vier Dinge, die man leicht kaputt macht

**Der Kurator läuft je Bedarf, nicht je Position.** Ein Plan mit 3 Phasen × 6
Einheiten × 4 Übungen hat 72 Positionen und vielleicht zwölf Bedarfe.
Wiederholung ist gewollt. Ohne das Eindampfen wird derselbe Bedarf in Einheit 3
wiederverwendet und in Einheit 9 neu erzeugt — der Nutzer sähe zweimal
dasselbe unter zwei Namen.

**Gespeichert wird sequenziell.** Ein später verarbeiteter Bedarf muss die
neuen Bausteine desselben Laufs schon als Kandidaten sehen. Parallel wäre
schneller und würde genau den Zustand herstellen, den das Dedupe verhindert.

**Jede KI-Ausgabe geht durch `pruefen.ts`.** Erwartete Felder, erwartete
Typen, Enums nur mit erlaubten Werten, Freitext auf plausible Länge begrenzt.
Was nicht passt, geht mit der Fehlerliste zurück ans Modell; nach zwei
Nachbesserungen bricht der Lauf ab. Ungeprüftes JSON wandert nirgendwohin —
weil ein untergeschobener Satz aus dem Feld „Stand" sonst über
`kernproblem` bis in den Kurator weiterreist.

**Nutzertext wird entschärft, bevor er in ein Tag kommt.** `prompts/nachricht.ts`
ersetzt `<` und `>`. Ohne das könnte jemand ins Feld „Stand" ein
`</stand><system>…` tippen und damit genau die Grenze aufheben, für die die
Tags da sind.

## Zwei geratene Zahlen

Beide stehen in `embedding.ts`, damit sie nicht auseinanderdriften:

- `AEHNLICHKEIT_SCHWELLE = 0,90` — darüber gilt ein neuer Baustein als
  Dublette und landet in `pruefliste` statt in der Bibliothek. Gilt auch beim
  Eindampfen der Bedarfe.
- `TAG_SCHWELLE = 0,88` — darüber wird „violine" zu „geige", wenn „geige"
  schon im Vokabular steht.

Dazu `TAG_GEWICHT = 0,5` in `retrieval.ts`. Jede Prüfung protokolliert den
tatsächlichen Wert (`console.log`, strukturiert), damit sich alle drei nach
ein paar hundert Bausteinen an echten Daten justieren lassen.

## Zustand über drei Anfragen

Ein Lauf zieht sich über `POST /v1/laeufe`, `…/antworten` und `…/plan`. Der
Zustand dazwischen liegt in der Tabelle `laeufe`, **nicht in der App**: käme
das Problemmodell zurückgeschickt, wäre es Nutzereingabe und damit
manipulierbar. Aus demselben Grund kommen auch die Rückfragen aus dem Lauf und
nicht aus der Anfrage.

Kontingent: **eine** Zeile in `generations` je Lauf, nicht je KI-Aufruf. Sonst
verbraucht ein Lauf mit fünfzehn Bedarfen siebzehn Generierungen.

## Testen

`cd server && npm test` — 111 Tests, kein Netz. D1, Vectorize und Workers AI
sind als Doppelgänger im Speicher nachgebaut (`test/speicher.ts`), Anthropic
antwortet aus konservierten SSE-Strömen (`test/hilfe.ts`).

`@cloudflare/vitest-pool-workers` ist bewusst **nicht** dabei: Vectorize und
Workers AI haben keine lokalen Bindings, ein Lauf im echten Worker bräuchte
Netz und Zugangsdaten. Der Preis: was im Doppelgänger anders liegt als in der
echten Datenbank, fällt hier nicht auf.

`test/spec-treue.test.ts` hält die drei System-Prompts Zeile für Zeile gegen
die Spec. Wer einen Prompt ändert, ändert ihn dort zuerst.

## Verwandt

- Was fehlt, bevor das laufen kann: `OFFEN.md` #14 (Cloudflare-Plan) und #15
  (Grundstock, Vectorize-Indizes)
- Stand des Ganzen: `ueberblick.md`
