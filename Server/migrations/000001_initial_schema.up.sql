-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users
CREATE TABLE users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_sub    TEXT UNIQUE NOT NULL,
    handle       TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_handle ON users (LOWER(handle));

-- Devices (max 2 per user: phone + desktop)
CREATE TABLE devices (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_type  TEXT NOT NULL CHECK (device_type IN ('phone', 'desktop')),
    apns_token   TEXT,
    last_seen_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_type)
);

-- Signal Protocol: identity keys per device
CREATE TABLE identity_keys (
    device_id  UUID PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    public_key BYTEA NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Signal Protocol: signed pre-keys per device
CREATE TABLE signed_pre_keys (
    id         SERIAL PRIMARY KEY,
    device_id  UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    key_id     INT NOT NULL,
    public_key BYTEA NOT NULL,
    signature  BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (device_id, key_id)
);

-- Signal Protocol: one-time pre-keys per device
CREATE TABLE one_time_pre_keys (
    id         SERIAL PRIMARY KEY,
    device_id  UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    key_id     INT NOT NULL,
    public_key BYTEA NOT NULL,
    used       BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (device_id, key_id)
);

-- Offline message envelopes (server never sees plaintext)
CREATE TABLE message_envelopes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id      UUID NOT NULL,
    sender_device_id    UUID NOT NULL,
    recipient_device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    payload             BYTEA NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_envelopes_recipient ON message_envelopes (recipient_device_id, created_at);

-- Auto-expire envelopes after 30 days (requires pg_cron or app-level cleanup;
-- we add a created_at index to support efficient deletion)
CREATE INDEX idx_envelopes_created_at ON message_envelopes (created_at);

-- Contacts
CREATE TABLE contacts (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    added_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, contact_user_id)
);

-- Call events (server-side record for missed-call push only)
CREATE TABLE call_events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id  UUID NOT NULL REFERENCES users(id),
    callee_id  UUID NOT NULL REFERENCES users(id),
    call_type  TEXT NOT NULL CHECK (call_type IN ('voice', 'video')),
    status     TEXT NOT NULL CHECK (status IN ('answered', 'missed', 'declined')),
    started_at TIMESTAMPTZ,
    ended_at   TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
