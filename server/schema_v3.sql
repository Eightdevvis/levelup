-- Die Bibliothek nach `lernprogramm-generator-spec.md` (Rev. 2).
--
-- Anwenden:  npx wrangler d1 execute levelup --remote --file=schema_v3.sql
--
-- Eigene Datei, weil die vorherigen Schemata nicht wiederholbar sind (ALTER
-- TABLE). Wer bei null anfängt, spielt schema.sql, schema_v2.sql und diese
-- Datei der Reihe nach ein.
--
-- Das Neue gegenüber v2: die Übung ist ein eigenes Objekt mit eigener
-- Lebensdauer, nicht mehr Nebenprodukt eines Plans. Deshalb deutsche
-- Feldnamen — sie sind die Feldnamen der Spec, und jede Übersetzung an der
-- Grenze zur Datenbank wäre eine Fehlerquelle mehr.

-- Der Baustein. Flach: über der Übung gibt es keine Hierarchie, Struktur
-- entsteht erst im Programm (Spec §2).
CREATE TABLE IF NOT EXISTS uebungen (
  id                TEXT PRIMARY KEY,
  titel             TEXT NOT NULL,
  anleitung         TEXT NOT NULL,
  benefit           TEXT NOT NULL,
  tags              TEXT NOT NULL,            -- JSON-Array, kleingeschrieben
  equipment         TEXT NOT NULL DEFAULT '[]', -- JSON-Array; leer heißt: bloße Hände
  bild              TEXT,
  animation         TEXT,
  created_at        INTEGER NOT NULL,
  -- Wie oft ein Plan diesen Baustein verwendet hat. Einmal pro Lauf, nicht
  -- pro Position — sonst gewinnt eine Übung, die in einem einzigen Plan
  -- zwanzigmal vorkommt, jede Rangfolge.
  usage_count       INTEGER NOT NULL DEFAULT 0,
  -- Aus welchem Programm er zuerst entstand. Nachvollziehbarkeit, nicht Besitz.
  source_program_id TEXT,
  -- Welches Gerät ihn ausgelöst hat. Nicht zum Anzeigen, sondern damit sich
  -- eine Quelle im Zweifel ausräumen lässt.
  source_device_id  TEXT,
  -- aktiv | zurueckgestellt. Zurückgestellte fallen aus dem Retrieval, ohne
  -- dass Verweise aus alten Plänen ins Leere zeigen.
  status            TEXT NOT NULL DEFAULT 'aktiv'
);

CREATE INDEX IF NOT EXISTS idx_uebungen_status ON uebungen(status);
CREATE INDEX IF NOT EXISTS idx_uebungen_usage ON uebungen(usage_count);

-- Das gewachsene Tag-Vokabular. Ohne diese Tabelle driften "geige",
-- "violine" und "streichinstrument" auseinander und die Suche findet nichts
-- mehr wieder (Spec §9). `count` sagt, wie eingebürgert ein Tag ist —
-- bei zwei ähnlichen gewinnt der häufigere.
CREATE TABLE IF NOT EXISTS tagvokabular (
  tag        TEXT PRIMARY KEY,
  count      INTEGER NOT NULL DEFAULT 0,
  -- Tätigkeits-Tags ("geige", "krafttraining") benennen die Domäne und
  -- werden in der App zu Exercise.domain. 0 für alles andere.
  ist_taetigkeit INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Ein Lauf ist ein Vorgang über mehrere Anfragen: Diagnose, ggf.
-- Rückfragen, dann der Plan. Ohne diese Tabelle müsste die App das
-- Problemmodell zwischenlagern und zurückschicken — und damit wäre es
-- Nutzereingabe, die sich manipulieren ließe.
CREATE TABLE IF NOT EXISTS laeufe (
  id            TEXT PRIMARY KEY,
  device_id     TEXT NOT NULL REFERENCES devices(id),
  created_at    INTEGER NOT NULL,
  -- diagnose | rueckfragen | plan | fertig | fehlgeschlagen
  status        TEXT NOT NULL,
  eingabe       TEXT NOT NULL,          -- die vier Felder aus §3, JSON
  rueckfragen   TEXT,                   -- JSON-Array, solange offen
  problemmodell TEXT,                   -- JSON, Ergebnis von [1] bzw. [1b]
  architektur   TEXT,                   -- JSON, Ergebnis von [2]
  -- Die Zeile in `generations`, gegen die dieser Lauf abgerechnet wird.
  -- Eine pro Lauf, nicht eine pro KI-Aufruf.
  generation_id TEXT,
  bundle_id     TEXT
);

CREATE INDEX IF NOT EXISTS idx_laeufe_device_time ON laeufe(device_id, created_at);

-- Was der Dedupe-Schritt nicht selbst entscheiden darf. Ab Ähnlichkeit 0,90
-- wird der neue Baustein nicht gespeichert, sondern hier hinterlegt: bei
-- Übungen liegen echte Varianten und echte Dubletten dicht beieinander, und
-- eine Maschine, die das automatisch verwirft, verliert Varianten (§9).
CREATE TABLE IF NOT EXISTS pruefliste (
  id           TEXT PRIMARY KEY,
  created_at   INTEGER NOT NULL,
  lauf_id      TEXT,
  kandidat     TEXT NOT NULL,           -- der neue Baustein als JSON
  bestand_id   TEXT NOT NULL REFERENCES uebungen(id),
  aehnlichkeit REAL NOT NULL,
  -- offen | eigenstaendig | verworfen
  status       TEXT NOT NULL DEFAULT 'offen'
);

CREATE INDEX IF NOT EXISTS idx_pruefliste_status ON pruefliste(status, created_at);

-- Die vier Kennzahlen aus §11, je Lauf festgehalten. Als Zeitreihe, nicht als
-- Momentaufnahme: die Wiederverwendungsquote soll steigen, und das sieht man
-- nur im Verlauf.
CREATE TABLE IF NOT EXISTS lauf_kennzahlen (
  lauf_id           TEXT PRIMARY KEY REFERENCES laeufe(id),
  created_at        INTEGER NOT NULL,
  bedarfe           INTEGER NOT NULL DEFAULT 0,
  reuse             INTEGER NOT NULL DEFAULT 0,
  neu               INTEGER NOT NULL DEFAULT 0,
  neue_tags         INTEGER NOT NULL DEFAULT 0,
  pruefliste        INTEGER NOT NULL DEFAULT 0,
  uebungspositionen INTEGER NOT NULL DEFAULT 0
);
