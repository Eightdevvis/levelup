-- Der geteilte Pool: das Gedächtnis, aus dem neue Pläne schöpfen.
--
-- Anwenden:  npx wrangler d1 execute levelup --remote --file=schema_v2.sql
--
-- Getrennt von schema.sql, weil ALTER TABLE nicht wiederholbar ist. Wer bei
-- null anfängt, spielt beide der Reihe nach ein.

-- Übungen sind die Bausteine und immer allgemein formuliert — "Rhythmus
-- klopfen" verrät nichts über die Person, die es gebraucht hat. Sie wandern
-- deshalb ungefragt in den Pool.
CREATE TABLE IF NOT EXISTS pool_exercises (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  domain      TEXT,
  summary     TEXT,
  tags        TEXT,                       -- kommagetrennt
  json        TEXT NOT NULL,              -- die vollständige Übung
  created_at  INTEGER NOT NULL,
  -- Wer es beigesteuert hat. Nicht zum Anzeigen, sondern damit sich eine
  -- Quelle nachvollziehen und im Zweifel ausräumen lässt.
  device_id   TEXT,
  -- Wie oft schon wiederverwendet. Sortiert die Suche: was sich bewährt hat,
  -- steht oben.
  used_count  INTEGER NOT NULL DEFAULT 0,
  -- name + summary + tags + domain, kleingeschrieben. Ein eigenes Feld, damit
  -- die Suche nicht vier Spalten einzeln durchgehen muss.
  search      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pool_exercises_domain ON pool_exercises(domain);
CREATE INDEX IF NOT EXISTS idx_pool_exercises_used ON pool_exercises(used_count);

-- Ganze Pläne. Landen hier erst, wenn jemand sie angenommen hat: was
-- weggeworfen wurde, soll niemand als Vorlage bekommen.
--
-- Der persönliche Teil der Antwort wird vorher entfernt und liegt nur auf dem
-- Gerät. Was hier steht, ist bewusst allgemein gehalten.
CREATE TABLE IF NOT EXISTS pool_programs (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  domain      TEXT,
  description TEXT,
  rationale   TEXT,
  tags        TEXT,
  weeks       INTEGER NOT NULL DEFAULT 0,
  json        TEXT NOT NULL,              -- vollständiges Bundle zum Übernehmen
  created_at  INTEGER NOT NULL,
  device_id   TEXT,
  used_count  INTEGER NOT NULL DEFAULT 0,
  search      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pool_programs_domain ON pool_programs(domain);
CREATE INDEX IF NOT EXISTS idx_pool_programs_used ON pool_programs(used_count);

-- Eine Überarbeitung ist ein anderer Vorgang als eine Erzeugung: sie schreibt
-- nur einen Patch und kostet einen Bruchteil. Beides zählt gegen das
-- Kontingent, aber die Abrechnung soll später unterscheiden können.
ALTER TABLE generations ADD COLUMN kind TEXT NOT NULL DEFAULT 'plan';
