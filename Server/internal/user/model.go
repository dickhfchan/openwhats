package user

import "time"

type User struct {
	ID          string    `json:"user_id"`
	AppleSub    string    `json:"-"`
	Handle      string    `json:"handle"`
	DisplayName string    `json:"display_name"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type Device struct {
	ID         string     `json:"device_id"`
	UserID     string     `json:"user_id"`
	DeviceType string     `json:"device_type"`
	APNSToken  *string    `json:"apns_token,omitempty"`
	LastSeenAt *time.Time `json:"last_seen_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}
