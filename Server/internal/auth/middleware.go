package auth

import (
	"net/http"
	"strings"

	"github.com/openwhats/server/internal/ctxkey"
)

// Middleware returns an HTTP middleware that validates the Bearer JWT.
// It injects user_id and optionally device_id into the request context.
func Middleware(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token := bearerToken(r)
			if token == "" {
				http.Error(w, `{"error":"missing authorization"}`, http.StatusUnauthorized)
				return
			}

			claims, err := ParseToken(token, secret)
			if err != nil {
				http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
				return
			}

			ctx := ctxkey.SetUserID(r.Context(), claims.UserID)
			if deviceID := r.Header.Get("X-Device-ID"); deviceID != "" {
				ctx = ctxkey.SetDeviceID(ctx, deviceID)
			}
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if after, ok := strings.CutPrefix(h, "Bearer "); ok {
		return strings.TrimSpace(after)
	}
	return ""
}
