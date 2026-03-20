-- Track committed media objects so we can issue download URLs only for valid uploads.
CREATE TABLE media_objects (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uploader_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    s3_key       TEXT UNIQUE NOT NULL,
    mime_type    TEXT NOT NULL,
    size_bytes   BIGINT NOT NULL,
    committed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON media_objects(uploader_id, created_at);
