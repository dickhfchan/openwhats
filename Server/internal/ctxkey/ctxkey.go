// Package ctxkey defines shared request context keys used across packages.
package ctxkey

import "context"

type key string

const (
	UserID   key = "user_id"
	DeviceID key = "device_id"
)

func SetUserID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, UserID, id)
}

func SetDeviceID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, DeviceID, id)
}

func GetUserID(ctx context.Context) string {
	v, _ := ctx.Value(UserID).(string)
	return v
}

func GetDeviceID(ctx context.Context) string {
	v, _ := ctx.Value(DeviceID).(string)
	return v
}
