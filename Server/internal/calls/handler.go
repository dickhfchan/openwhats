package calls

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/openwhats/server/internal/ctxkey"
	"go.uber.org/zap"
)

// Handler returns TURN credentials for WebRTC ICE negotiation.
type Handler struct {
	turnHost string
	secret   []byte
	logger   *zap.Logger
}

func NewHandler(logger *zap.Logger) *Handler {
	return &Handler{
		turnHost: getenv("TURN_HOST", "3.222.228.217"),
		secret:   []byte(getenv("TURN_SECRET", "change-me-in-production")),
		logger:   logger,
	}
}

// TURNCredentials are short-lived HMAC-SHA1 credentials understood by coturn
// (--use-auth-secret mode). See RFC 8489 §9.2.
type TURNCredentials struct {
	Username string   `json:"username"` // "<expiry>:<userID>"
	Password string   `json:"password"` // base64(HMAC-SHA1(secret, username))
	TTL      int      `json:"ttl"`      // seconds until expiry
	URIs     []string `json:"uris"`
}

// HandleTURNCredentials handles GET /calls/turn-credentials.
func (h *Handler) HandleTURNCredentials(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())

	const ttl = 86400 // 24 h
	expiry := time.Now().Unix() + ttl
	username := fmt.Sprintf("%d:%s", expiry, userID)

	mac := hmac.New(sha1.New, h.secret)
	mac.Write([]byte(username))
	password := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	uris := []string{
		fmt.Sprintf("stun:%s:3478", h.turnHost),
		fmt.Sprintf("turn:%s:3478", h.turnHost),
		fmt.Sprintf("turn:%s:3478?transport=tcp", h.turnHost),
		fmt.Sprintf("turns:%s:5349", h.turnHost),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(TURNCredentials{
		Username: username,
		Password: password,
		TTL:      ttl,
		URIs:     uris,
	})
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Ensure zap import is used via logger field only.
var _ = zap.String
