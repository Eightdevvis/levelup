# LevelUp-API

Der kleine Server, über den die App Pläne erzeugt. Er hält den
Anthropic-Schlüssel, damit ihn niemand sonst braucht, und zählt mit, wie viel
jedes Gerät verbraucht.

## Warum es das gibt

Die App ist nicht nur für eine Person. Ein Schlüsselfeld in der App würde
bedeuten, dass sich jeder erst ein Anthropic-Entwicklerkonto anlegt — das macht
niemand. Und der eigene Schlüssel in einer veröffentlichten App wäre nach einem
Tag abgegriffen: eine App ist ein Paket auf fremden Geräten, nichts darin ist
geheim.

Also liegt der Schlüssel hier. Die App weist sich mit einem Gerätetoken aus, das
sie beim ersten Öffnen einmal bekommt — **keine Anmeldung, keine E-Mail, kein
Passwort**. Die Spalte `user_id` in `devices` ist bewusst schon da und bleibt
leer: wenn später Konten dazukommen, werden bestehende Geräte daran geknüpft,
statt dass alle ihr Guthaben verlieren.

## Was drin ist

| Endpunkt | Zweck |
|---|---|
| `POST /v1/devices` | Einmalige Geräteanmeldung. Gibt das Token **genau einmal** zurück — gespeichert wird nur sein SHA-256. |
| `GET /v1/me` | Was das Kontingent noch hergibt. |
| `POST /v1/generate` | Plan erzeugen. Reicht den Ereignisstrom von Anthropic durch und misst dabei den Verbrauch. |

Zwei Dinge, die bewusst so sind:

- **Der Systemprompt liegt hier**, nicht in der App (`src/plan_prompt.ts`). Sonst
  könnte man ihn austauschen und den Schlüssel des Betreibers für beliebige
  Textproduktion benutzen. Er muss inhaltlich mit `lib/data/ai_prompt.dart`
  übereinstimmen — dort steht dieselbe Vorlage für den Weg über Kopieren und
  Einfügen.
- **Fehlgeschlagene Läufe zählen nicht.** `quotaFor()` überspringt Zeilen mit
  `status='failed'`. Wer nichts bekommen hat, soll nichts bezahlen.

## Ausrollen

Braucht ein Cloudflare-Konto. Der Reihe nach, aus `server/`:

```bash
npx wrangler login                  # öffnet den Browser
npx wrangler d1 create levelup      # gibt eine database_id aus
```

Die ausgegebene `database_id` in `wrangler.jsonc` eintragen — sie steht dort
noch als Platzhalter.

```bash
npx wrangler d1 execute levelup --remote --file=schema.sql
npx wrangler secret put ANTHROPIC_API_KEY   # Schlüssel aus der Anthropic-Konsole
npx wrangler deploy
```

`deploy` gibt die URL aus. Die gehört in `lib/data/plan_service.dart` als
`defaultBaseUrl` — solange dort die Platzhalter-URL steht, kommt die App nicht
an den Server.

## Stellschrauben

Stehen als `vars` in `wrangler.jsonc` und lassen sich ohne Codeänderung drehen:

| Name | Bedeutung |
|---|---|
| `FREE_GENERATIONS` | Wie viele Pläne ein neues Gerät umsonst bekommt |
| `DAILY_LIMIT` | Obergrenze pro Gerät und Tag |
| `MAX_REQUEST_CHARS` | Wie lang eine Anfrage sein darf |
| `MAX_OUTPUT_TOKENS` | Deckel für Denken und Antwort zusammen |

## Örtlich ausprobieren

```bash
npx wrangler dev --local
```

`--local` heißt: eine D1 auf der Platte statt der echten. Für einen echten
Erzeugungslauf muss ein gültiger `ANTHROPIC_API_KEY` in `.dev.vars` stehen —
die Datei ist absichtlich nicht im Repo. Ohne gültigen Schlüssel antwortet
`/v1/generate` mit `502 upstream`, und das Kontingent bleibt unangetastet: genau
das ist der Beweis, dass ein Fehlschlag nichts kostet.

## Was noch fehlt

- **Bezahlen.** Verteilt wird über Play Store und App Store, und beide verlangen
  für digitale Güter ihre eigene Abrechnung (15–30 %). Also Google Play Billing
  und StoreKit, kein Stripe. Der Beleg wird hier geprüft, danach wächst das
  Guthaben in einem Kontobuch.
- **Datenschutz.** Wer den Server betreibt, ist Verantwortlicher im Sinne der
  DSGVO. Vor der Veröffentlichung braucht es eine Datenschutzerklärung, einen
  Auftragsverarbeitungsvertrag mit Anthropic und Cloudflare und eine Antwort auf
  die Frage, wie lange die Zeilen in `generations` liegen bleiben.
