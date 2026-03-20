DROP INDEX IF EXISTS idx_users_handle;
ALTER TABLE users ALTER COLUMN handle SET NOT NULL;
ALTER TABLE users ALTER COLUMN display_name SET NOT NULL;
CREATE INDEX idx_users_handle ON users (LOWER(handle));
