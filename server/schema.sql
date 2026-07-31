-- Schema der LevelUp-API.
--
-- Anwenden:  npx wrangler d1 execute levelup --remote --file=schema.sql
--
-- Phase 1 kennt keine Anmeldung: ein Gerät registriert sich einmal und bekommt
-- ein Token. Die Spalte `user_id` ist bewusst schon da und bleibt leer — wenn
-- später E-Mail-Konten dazukommen, werden bestehende Geräte daran geknüpft,
-- statt dass alle ihr Guthaben verlieren.

CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,           -- dev_<zufall>
  token_hash    TEXT NOT NULL UNIQUE,       -- SHA-256 des Tokens, nie das Token selbst
  user_id       TEXT,                       -- für später: Konto-Verknüpfung
  platform      TEXT,                       -- android | ios | linux | …
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- Eine Zeile je Erzeugungsversuch. Dient drei Zwecken gleichzeitig:
-- Kontingentzählung, Tageslimit und Kostennachweis.
CREATE TABLE IF NOT EXISTS generations (
  id             TEXT PRIMARY KEY,
  device_id      TEXT NOT NULL REFERENCES devices(id),
  created_at     INTEGER NOT NULL,
  -- Wird erst nach dem Strom gefüllt; bleibt 0, wenn der Lauf abbrach.
  input_tokens   INTEGER NOT NULL DEFAULT 0,
  output_tokens  INTEGER NOT NULL DEFAULT 0,
  cache_read     INTEGER NOT NULL DEFAULT 0,
  cache_write    INTEGER NOT NULL DEFAULT 0,
  status         TEXT NOT NULL DEFAULT 'running',  -- running | done | failed
  stop_reason    TEXT
);

CREATE INDEX IF NOT EXISTS idx_generations_device_time
  ON generations(device_id, created_at);
