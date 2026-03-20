package user

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

var ErrNotFound = errors.New("not found")
var ErrHandleTaken = errors.New("handle already taken")
var ErrNotRegistered = errors.New("user has not completed registration")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// CreateUnregistered inserts a minimal user row (no handle) immediately after Apple auth.
// The user must call SetHandleAndName to complete onboarding.
func (r *Repository) CreateUnregistered(ctx context.Context, appleSub string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO users (apple_sub)
		 VALUES ($1)
		 ON CONFLICT (apple_sub) DO UPDATE SET apple_sub = EXCLUDED.apple_sub
		 RETURNING id, apple_sub, COALESCE(handle,''), COALESCE(display_name,''), avatar_url, created_at`,
		appleSub,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	return &u, err
}

// SetHandleAndName completes onboarding by setting the handle and display name.
func (r *Repository) SetHandleAndName(ctx context.Context, userID, handle, displayName string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`UPDATE users SET handle = LOWER($2), display_name = $3
		 WHERE id = $1
		 RETURNING id, apple_sub, handle, display_name, avatar_url, created_at`,
		userID, handle, displayName,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "unique") && strings.Contains(err.Error(), "handle") {
			return nil, ErrHandleTaken
		}
		return nil, fmt.Errorf("set handle: %w", err)
	}
	return &u, nil
}

func (r *Repository) Create(ctx context.Context, appleSub, handle, displayName string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO users (apple_sub, handle, display_name)
		 VALUES ($1, LOWER($2), $3)
		 RETURNING id, apple_sub, handle, display_name, avatar_url, created_at`,
		appleSub, handle, displayName,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "unique") && strings.Contains(err.Error(), "handle") {
			return nil, ErrHandleTaken
		}
		return nil, fmt.Errorf("create user: %w", err)
	}
	return &u, nil
}

func (r *Repository) GetByAppleSub(ctx context.Context, appleSub string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`SELECT id, apple_sub, handle, display_name, avatar_url, created_at
		 FROM users WHERE apple_sub = $1`, appleSub,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &u, err
}

func (r *Repository) GetByID(ctx context.Context, id string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`SELECT id, apple_sub, handle, display_name, avatar_url, created_at
		 FROM users WHERE id = $1`, id,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &u, err
}

func (r *Repository) GetByHandle(ctx context.Context, handle string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`SELECT id, apple_sub, handle, display_name, avatar_url, created_at
		 FROM users WHERE LOWER(handle) = LOWER($1)`, handle,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &u, err
}

func (r *Repository) HandleExists(ctx context.Context, handle string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM users WHERE LOWER(handle) = LOWER($1))`, handle,
	).Scan(&exists)
	return exists, err
}

func (r *Repository) Update(ctx context.Context, id, displayName string, avatarURL *string) (*User, error) {
	var u User
	err := r.db.QueryRowContext(ctx,
		`UPDATE users SET display_name = $2, avatar_url = COALESCE($3, avatar_url)
		 WHERE id = $1
		 RETURNING id, apple_sub, handle, display_name, avatar_url, created_at`,
		id, displayName, avatarURL,
	).Scan(&u.ID, &u.AppleSub, &u.Handle, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &u, err
}

// --- Device ---

func (r *Repository) CreateDevice(ctx context.Context, userID, deviceType string, apnsToken *string) (*Device, error) {
	var d Device
	// Upsert: if same device_type exists for user, replace it
	err := r.db.QueryRowContext(ctx,
		`INSERT INTO devices (user_id, device_type, apns_token)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, device_type)
		 DO UPDATE SET apns_token = EXCLUDED.apns_token, last_seen_at = now()
		 RETURNING id, user_id, device_type, apns_token, last_seen_at, created_at`,
		userID, deviceType, apnsToken,
	).Scan(&d.ID, &d.UserID, &d.DeviceType, &d.APNSToken, &d.LastSeenAt, &d.CreatedAt)
	return &d, err
}

func (r *Repository) GetDevicesByUserID(ctx context.Context, userID string) ([]Device, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT id, user_id, device_type, apns_token, last_seen_at, created_at
		 FROM devices WHERE user_id = $1 ORDER BY created_at`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.DeviceType, &d.APNSToken, &d.LastSeenAt, &d.CreatedAt); err != nil {
			return nil, err
		}
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

func (r *Repository) DeleteDevice(ctx context.Context, deviceID, userID string) error {
	res, err := r.db.ExecContext(ctx,
		`DELETE FROM devices WHERE id = $1 AND user_id = $2`, deviceID, userID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) UpdateLastSeen(ctx context.Context, deviceID string) {
	r.db.ExecContext(ctx,
		`UPDATE devices SET last_seen_at = now() WHERE id = $1`, deviceID,
	)
}

func (r *Repository) UpdateAPNSToken(ctx context.Context, deviceID, userID, token string) error {
	res, err := r.db.ExecContext(ctx,
		`UPDATE devices SET apns_token = $3 WHERE id = $1 AND user_id = $2`,
		deviceID, userID, token,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}
