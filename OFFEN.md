# Was noch offen ist

Stand: 02.08.2026, nach dem Umbau des Backends auf Spec Rev. 2.

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

### 2. Jeder kann in die geteilte Bibliothek schreiben

`POST /v1/plans/accept` nimmt jedes Bundle an, das nach einem Plan aussieht. Es
gibt keinen Nachweis, dass der Plan aus einem eigenen Lauf stammt. Wer will,
kippt Unsinn in die Bibliothek, aus der dann alle anderen schöpfen.

**Seit Rev. 2 dringlicher.** Übungen wandern jetzt schon während des Laufs in
`uebungen`, nicht erst beim Annehmen — das ist so gewollt (§1), heißt aber:
Punkt 1 oben deckelt nicht mehr nur die Kosten, sondern auch, wie viel Unsinn
in der Bibliothek landen kann. Wer beliebig viele Geräte anlegt, kann beliebig
viele Bausteine erzeugen. Das Zurückstellen (`status = 'zurueckgestellt'`) und
die Herkunft (`source_device_id`) sind da, das Aufräumen von Hand ist es
noch nicht.

Abgefedert ist es nur halb: jede Zeile trägt ihre `device_id`, eine schlechte
Quelle lässt sich also finden und ausräumen. Das ist Aufräumen im Nachhinein,
keine Verhinderung.

Der saubere Weg: beim Erzeugen einen Fingerabdruck des Plans mitschreiben und
beim Annehmen verlangen. Haken dabei — nach einer Überarbeitung stimmt der
Fingerabdruck nicht mehr, weil der Patch auf dem Gerät angewendet wird. Also
entweder der Server wendet ihn zum Mitschreiben ebenfalls an, oder es reicht ein
loserer Nachweis (dieses Gerät hatte in den letzten 24 Stunden einen
erfolgreichen Lauf).

### 14. Workers Free reicht für den Plan-Endpunkt nicht

Gemessen an einem Lauf mit 3 Phasen × 6 Einheiten × 4 Übungen (72 Positionen,
12 eindeutige Bedarfe, 4 wiederverwendet) — `server/test/aufwand.test.ts`:

| | |
|---|---|
| D1-Abfragen | 56 |
| Anthropic-Aufrufe | 13 |
| Workers AI | 17 |
| Vectorize | 44 |
| **eng gezählt** (nur D1 + fetch) | **69** |
| **weit gezählt** (alle Bindings) | **130** |
| Grenze Free | 50 |
| Grenze Paid | 10.000 |

Die Doku zählt „jede Anfrage über die Fetch-API oder an Cloudflare-Dienste
wie R2, KV oder D1". Vectorize und Workers AI stehen nicht ausdrücklich dabei,
das „wie" macht die Liste aber offen — die sichere Annahme ist die weite
Zählung. **Beide Lesarten liegen über 50.**

Dazu kommt die CPU-Grenze: Free erlaubt 10 ms je Aufruf. Allein das Lesen von
dreizehn SSE-Strömen mit zusammen rund 16.000 Ausgabe-Token liegt darüber,
noch vor dem Kosinus über die Bedarfsvektoren. **Free ist damit nicht knapp,
sondern um mehr als eine Größenordnung daneben.**

Was funktioniert: `POST /v1/laeufe` (Diagnose) ist ein Anthropic-Aufruf und
vier D1-Abfragen. Nur der Plan-Endpunkt sprengt den Rahmen.

Drei Wege:

1. **Workers Paid, 5 $/Monat.** Dafür ist alles gebaut. Empfohlen.
2. Die Pipeline über viele Anfragen stückeln und die App die Schleife treiben
   lassen. Löst die Unteranfragen, **nicht** die 10 ms CPU, und macht die App
   wieder zum Zustandshalter — genau das, was Rev. 2 abgeschafft hat.
3. Kleinere Pläne. Verschiebt die Grenze, reißt sie aber weiter.

---

### 16. Was ein Plan kostet — und woran das hängt

Gemessen am selben Lauf (`server/test/aufwand.test.ts`), Preise Opus 5
(5 $/M Eingabe, 25 $/M Ausgabe):

| Posten | Token | |
|---|---|---|
| Eingabe Diagnose | 481 | |
| Eingabe Architekt | 939 | |
| Eingabe Kurator (12 Aufrufe) | 31.246 | fast alles Kandidatenlisten |
| Eingabe gesamt | 32.666 | 0,16 $ |
| Ausgabe gesamt | 15.887 | 0,40 $ |
| **Summe** | | **≈ 0,56 $ je Plan** |

Die Texte sind gemessen, nur die Denk-Token sind geschätzt (1.200 Diagnose,
2.500 Architekt, 700 je Kurator-Aufruf) — sie machen 12.100 der 15.887
Ausgabe-Token aus und sind damit der größte Einzelposten. **Der Rechenweg ist
also nur so gut wie diese Schätzung**; die echten Zahlen stehen nach dem
ersten Lauf in `generations`.

Grob: fester Anteil (Diagnose + Architekt) ≈ 0,15 $, dazu ≈ 0,036 $ je
eindeutigem Bedarf.

Drei Hebel, falls es zu teuer wird:

- **Kurator auf Sonnet 5** statt Opus: ≈ 0,34 $ statt 0,56 $. Er wählt
  überwiegend aus einer vorgelegten Liste aus — die Aufgabe, bei der der
  Abstand zwischen den Modellen am kleinsten ist.
- **Weniger Denken beim Kurator.** 8.400 der Ausgabe-Token sind seine
  Gedankengänge, also gut 0,20 $ je Plan.
- **Kürzere Kandidatenlisten.** Zehn volle Anleitungen sind 31.000 der 32.666
  Eingabe-Token; bei fünf halbiert sich der Eingabeanteil. Kostet aber
  Wiederverwendung, und die ist der Sinn der Sache.

**Der eigentliche Kostenposten ist nicht der Plan, sondern Punkt 1.**
`FREE_GENERATIONS` steht auf 3, macht ≈ 1,70 $ je Gerät — und Geräte kann sich
jeder unbegrenzt anlegen.

---

### 15. Der Grundstock ist noch nicht eingespielt

`server/grundstock/*.json` liegt bereit (12 Bausteine Geige, 12
Krafttraining), das Skript auch. Vorher fehlen noch: die beiden
Vectorize-Indizes (`wrangler vectorize create uebungen --dimensions=1024
--metric=cosine`, dasselbe für `tagvokabular`, plus den Metadaten-Index auf
`status`), `schema_v3.sql` auf der entfernten Datenbank, und
`wrangler secret put BETREIBER_TOKEN`.

**Die 1024 sind ungeprüft.** Die Typdefinition von `bge-m3` nennt die
Vektorlänge nicht; sie steht erst im `shape` der ersten echten Antwort. Stimmt
sie nicht, nimmt Vectorize die Vektoren nicht an — dann Index löschen und mit
der richtigen Zahl neu anlegen, bevor Daten drin sind.

### 3. Datenschutz

Wer den Server betreibt, ist Verantwortlicher im Sinne der DSGVO. Offen:

- Datenschutzerklärung, in der App erreichbar
- Auftragsverarbeitungsverträge mit Anthropic und Cloudflare
- Eine Antwort darauf, wie lange Zeilen in `generations` liegen bleiben
- Ein Weg, ein Gerät und seine Daten zu löschen. Es gibt derzeit **keinen**
  Endpunkt dafür. Das Gerätetoken ist ein Pseudonym, damit personenbezogen.
- Die Bibliothek enthält von Nutzern beigesteuerte Inhalte. Auch wenn der persönliche
  Teil entfernt wird: die Frage, ob jemand seinen Beitrag zurückziehen kann,
  gehört beantwortet, bevor sie gestellt wird.

### 4. ~~Zwei Bibliotheken, die nichts voneinander wissen~~ — erledigt

Die App liest jetzt `GET /v1/library`, also denselben Pool, aus dem die AI
schöpft. Der statische Katalog auf GitHub ist weg.

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

### 8. Die Bibliothek wird nie aufgeräumt — halb erledigt

Dubletten fängt seit Rev. 2 das Dedupe ab: ab Ähnlichkeit 0,90 landet ein
Baustein in `pruefliste` statt in der Bibliothek, und `GET /v1/pruefliste`
zeigt die offenen Fälle. Was fehlt, ist alles darüber hinaus — keine
Qualitätsschwelle, kein Entfernen außer dem Zurückstellen von Hand, keine
Zusammenführung zweier Bausteine, die dasselbe meinen und es unter 0,90 tun.

Offen ist auch die Schwelle selbst. 0,90 ist geraten; jede Prüfung
protokolliert den tatsächlichen Wert, damit sie nach ein paar hundert
Bausteinen an echten Daten justiert werden kann. Bis dahin ist die Prüfliste
die einzige Rückmeldung darüber, ob sie zu hoch oder zu niedrig steht.

### 9. Kennungen können kollidieren

Die App führt Übungen per `id` zusammen. Übernimmt jemand einen Plan aus dem
Pool, der eine `id` benutzt, die er selbst schon anders belegt hat, wird seine
eigene Fassung überschrieben. Der Domänen-Präfix im Prompt
(`geige-rhythmus-klopfen`) macht es unwahrscheinlich, aber nicht unmöglich.

Sauber wäre, beim Zusammenführen zu erkennen, dass zwei Übungen mit gleicher
Kennung verschieden sind, und die hereinkommende umzubenennen.

### 10. Die Suche ist jetzt Vektoren — mit einem ungeeichten Gewicht

Statt Stichwörtern gegen ein Textfeld sucht `src/retrieval.ts` über Embeddings
und sortiert nach `score * (1 + 0,5 * Jaccard über die Tags)` um. Das Gewicht
0,5 ist ein Startwert und an echten Daten zu justieren: zu klein, und ein
Baustein aus fremder Tätigkeit rutscht wegen ähnlicher Formulierung nach oben;
zu groß, und die Suche findet nichts mehr außerhalb der schon vergebenen Tags.
Der Test hält den Fall aus §7.2 fest, mehr ist es noch nicht.

`src/pool.ts` sucht weiter mit Stichwörtern — es bedient nur noch die offene
Programmliste, nicht mehr die Übungen.

### 10b. ~~Die Übungsprüfung hat keinen automatischen Test~~ — erledigt

Der Worker hat jetzt eins: `npm test` in `server/` fährt 111 Tests, darunter
jede Schemaprüfung gültig und kaputt, das Eindampfen, die Reihung, das Dedupe
und ein Durchlauf über die ganze Pipeline mit konservierten KI-Antworten.

Was bewusst **nicht** dabei ist: `@cloudflare/vitest-pool-workers`. Vectorize
und Workers AI haben keine lokalen Bindings, ein Lauf im echten Worker bräuchte
also Netz und Zugangsdaten. D1, Vectorize und Workers AI sind stattdessen als
Doppelgänger im Speicher nachgebaut (`test/speicher.ts`). Der Preis: was dort
anders liegt als in der echten Datenbank, fällt hier nicht auf.

Der Fehler von damals bleibt lehrreich: die erste Fassung der Prüfung verglich
`requirements` mit dem Text und meldete bei einem echten Plan 25
Beanstandungen, darunter „Tastatur" bei einer Tipp-Übung. Ein Prüfer mit
überwiegend Fehlalarmen ist schlechter als keiner. Deshalb prüft `pruefen.ts`
nur Eindeutiges — Struktur, Typen, Enums, Längen — und lässt alles Inhaltliche
Prompt-Regel bleiben.

### 11. Zwei Wege, die auseinanderlaufen können — teilweise erledigt

Der Server hat seit Rev. 2 keinen einzelnen Prompt mehr, sondern drei
(Diagnose, Architekt, Kurator). Dass sie wortgleich in
`lernprogramm-generator-spec.md` stehen, prüft `server/test/spec-treue.test.ts`
Zeile für Zeile — inklusive der einen gewollten Abweichung.

`lib/data/ai_prompt.dart` ist der kostenlose Weg: Prompt in einen Chat, JSON
zurück in die App. Er kennt weder Bibliothek noch Rückkopplungsdiagnose und
läuft damit **inhaltlich** neben dem Server her. `test/prompt_drift_test.dart`
prüft nur noch, dass die alten Regeln darin stehen. Offen: ob dieser Weg
überhaupt bleiben soll, jetzt wo Server und App verschiedene Modelle vom
Lernen haben.

### 12. Was passiert, wenn die AI aufgibt — erledigt

Der Werkzeug-Agent mit `MAX_TURNS` ist weg. Jeder KI-Aufruf hat jetzt genau
eine Aufgabe und ein festes Ausgabeformat; hält die Ausgabe der Prüfung nach
zwei Nachbesserungen nicht stand, bricht der Lauf mit `unreadable` ab statt
mit einer irreführenden Meldung über die Erreichbarkeit.

### 13. Veröffentlichen

Entwicklerkonten bei Google und Apple, Signierung, Store-Einträge, Screenshots,
Altersfreigabe. Nichts davon ist angefangen.
