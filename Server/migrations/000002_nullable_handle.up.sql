-- Allow handle to be NULL for users who haven't completed onboarding yet.
-- The UNIQUE constraint remains so no two completed users can share a handle.
ALTER TABLE users ALTER COLUMN handle DROP NOT NULL;
ALTER TABLE users ALTER COLUMN display_name DROP NOT NULL;

-- Update the unique index to ignore NULL handles (Postgres NULL != NULL in unique index)
DROP INDEX IF EXISTS idx_users_handle;
CREATE UNIQUE INDEX idx_users_handle ON users (LOWER(handle)) WHERE handle IS NOT NULL AND handle != '';
