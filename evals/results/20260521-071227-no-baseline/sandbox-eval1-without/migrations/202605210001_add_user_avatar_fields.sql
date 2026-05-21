BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS avatar_mime_type VARCHAR(64),
  ADD COLUMN IF NOT EXISTS avatar_size_bytes INTEGER,
  ADD COLUMN IF NOT EXISTS avatar_updated_at TIMESTAMPTZ;

ALTER TABLE users
  ADD CONSTRAINT users_avatar_size_bytes_check
  CHECK (avatar_size_bytes IS NULL OR (avatar_size_bytes >= 0 AND avatar_size_bytes <= 5242880))
  NOT VALID;

ALTER TABLE users
  VALIDATE CONSTRAINT users_avatar_size_bytes_check;

CREATE INDEX IF NOT EXISTS idx_users_avatar_updated_at
  ON users (avatar_updated_at)
  WHERE avatar_updated_at IS NOT NULL;

COMMIT;
