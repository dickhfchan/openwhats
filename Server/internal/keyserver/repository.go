package keyserver

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

var ErrNoPreKeys = errors.New("no one-time pre-keys available")

type PreKeyBundle struct {
	DeviceID           string `json:"device_id"`
	DeviceType         string `json:"device_type"`
	IdentityKey        []byte `json:"identity_key"`         // 32-byte Curve25519 public key
	SignedPreKeyID     int    `json:"signed_pre_key_id"`
	SignedPreKey       []byte `json:"signed_pre_key"`       // 32-byte Curve25519 public key
	SignedPreKeySig    []byte `json:"signed_pre_key_sig"`   // 64-byte Ed25519 signature
	OneTimePreKeyID    *int   `json:"one_time_pre_key_id"`  // nil if exhausted
	OneTimePreKey      []byte `json:"one_time_pre_key"`     // 32-byte Curve25519 public key (nil if exhausted)
}

type OTPKUpload struct {
	KeyID     int    `json:"key_id"`
	PublicKey []byte `json:"public_key"`
}

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// UpsertIdentityKey stores or updates a device's identity key.
func (r *Repository) UpsertIdentityKey(ctx context.Context, deviceID string, publicKey []byte) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO identity_keys (device_id, public_key)
		 VALUES ($1, $2)
		 ON CONFLICT (device_id) DO UPDATE SET public_key = $2, updated_at = now()`,
		deviceID, publicKey,
	)
	return err
}

// UpsertSignedPreKey stores or replaces a device's signed pre-key.
func (r *Repository) UpsertSignedPreKey(ctx context.Context, deviceID string, keyID int, publicKey, signature []byte) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO signed_pre_keys (device_id, key_id, public_key, signature)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (device_id, key_id) DO UPDATE
		   SET public_key = $3, signature = $4`,
		deviceID, keyID, publicKey, signature,
	)
	return err
}

// InsertOneTimePreKeys bulk-inserts OTPKs for a device.
func (r *Repository) InsertOneTimePreKeys(ctx context.Context, deviceID string, keys []OTPKUpload) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx,
		`INSERT INTO one_time_pre_keys (device_id, key_id, public_key)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (device_id, key_id) DO NOTHING`,
	)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, k := range keys {
		if _, err := stmt.ExecContext(ctx, deviceID, k.KeyID, k.PublicKey); err != nil {
			return fmt.Errorf("insert otpk %d: %w", k.KeyID, err)
		}
	}
	return tx.Commit()
}

// CountOneTimePreKeys returns the number of unused OTPKs for a device.
func (r *Repository) CountOneTimePreKeys(ctx context.Context, deviceID string) (int, error) {
	var count int
	err := r.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM one_time_pre_keys WHERE device_id = $1 AND used = false`,
		deviceID,
	).Scan(&count)
	return count, err
}

// FetchBundlesForUser returns one pre-key bundle per registered device for the given user.
// It atomically marks one OTPK per device as used.
func (r *Repository) FetchBundlesForUser(ctx context.Context, userID string) ([]PreKeyBundle, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Get all devices for the user
	rows, err := tx.QueryContext(ctx,
		`SELECT d.id, d.device_type,
		        ik.public_key AS identity_key,
		        spk.key_id AS spk_id, spk.public_key AS spk_pub, spk.signature AS spk_sig
		 FROM devices d
		 JOIN identity_keys ik ON ik.device_id = d.id
		 JOIN signed_pre_keys spk ON spk.device_id = d.id
		 WHERE d.user_id = $1
		 ORDER BY spk.id DESC`, // latest signed pre-key per device
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Deduplicate by device_id (take the latest spk)
	seen := map[string]bool{}
	var bundles []PreKeyBundle
	for rows.Next() {
		var b PreKeyBundle
		if err := rows.Scan(&b.DeviceID, &b.DeviceType, &b.IdentityKey,
			&b.SignedPreKeyID, &b.SignedPreKey, &b.SignedPreKeySig); err != nil {
			return nil, err
		}
		if seen[b.DeviceID] {
			continue
		}
		seen[b.DeviceID] = true
		bundles = append(bundles, b)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// For each device, consume one OTPK
	for i := range bundles {
		keyID, pubKey, err := consumeOTPK(ctx, tx, bundles[i].DeviceID)
		if err != nil && !errors.Is(err, ErrNoPreKeys) {
			return nil, fmt.Errorf("consume otpk for device %s: %w", bundles[i].DeviceID, err)
		}
		bundles[i].OneTimePreKeyID = keyID
		bundles[i].OneTimePreKey = pubKey
	}

	return bundles, tx.Commit()
}

func consumeOTPK(ctx context.Context, tx *sql.Tx, deviceID string) (*int, []byte, error) {
	var keyID int
	var pubKey []byte
	err := tx.QueryRowContext(ctx,
		`UPDATE one_time_pre_keys SET used = true
		 WHERE id = (
		   SELECT id FROM one_time_pre_keys
		   WHERE device_id = $1 AND used = false
		   ORDER BY id
		   LIMIT 1
		   FOR UPDATE SKIP LOCKED
		 )
		 RETURNING key_id, public_key`,
		deviceID,
	).Scan(&keyID, &pubKey)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, ErrNoPreKeys
	}
	if err != nil {
		return nil, nil, err
	}
	return &keyID, pubKey, nil
}
