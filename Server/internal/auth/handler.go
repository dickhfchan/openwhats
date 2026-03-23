package auth

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/openwhats/server/internal/ctxkey"
	"github.com/openwhats/server/internal/user"
	"go.uber.org/zap"
)

type Handler struct {
	users     *user.Repository
	jwtSecret string
	bundleIDs []string
	logger    *zap.Logger
}

func NewHandler(users *user.Repository, jwtSecret string, appleBundleIDs string, logger *zap.Logger) *Handler {
	ids := strings.Split(appleBundleIDs, ",")
	for i := range ids {
		ids[i] = strings.TrimSpace(ids[i])
	}
	return &Handler{users: users, jwtSecret: jwtSecret, bundleIDs: ids, logger: logger}
}

type appleAuthRequest struct {
	IdentityToken string `json:"identity_token"`
}

type appleAuthResponse struct {
	Token      string `json:"token"`
	UserID     string `json:"user_id"`
	IsNewUser  bool   `json:"is_new_user"`
	IsComplete bool   `json:"is_complete"` // false if handle not yet set
}

// POST /auth/apple
func (h *Handler) HandleAppleAuth(w http.ResponseWriter, r *http.Request) {
	var req appleAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityToken == "" {
		http.Error(w, `{"error":"identity_token required"}`, http.StatusBadRequest)
		return
	}

	sub, err := VerifyAppleToken(r.Context(), req.IdentityToken, h.bundleIDs)
	if err != nil {
		h.logger.Warn("apple token verification failed", zap.Error(err))
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	isNew := false
	u, err := h.users.GetByAppleSub(r.Context(), sub)
	if err == user.ErrNotFound {
		// Create a placeholder user; handle must be set via /users/register
		u, err = h.users.CreateUnregistered(r.Context(), sub)
		if err != nil {
			h.logger.Error("create unregistered user", zap.Error(err))
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		isNew = true
	} else if err != nil {
		h.logger.Error("lookup user by apple sub", zap.Error(err))
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	token, err := IssueToken(u.ID, h.jwtSecret)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, appleAuthResponse{
		Token:      token,
		UserID:     u.ID,
		IsNewUser:  isNew,
		IsComplete: u.Handle != "",
	})
}

// POST /auth/debug-token — decodes Apple JWT claims without verification (DEBUG only)
func (h *Handler) HandleDebugToken(w http.ResponseWriter, r *http.Request) {
	var req appleAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityToken == "" {
		http.Error(w, `{"error":"identity_token required"}`, http.StatusBadRequest)
		return
	}
	_, claims, err := jwt.NewParser().ParseUnverified(req.IdentityToken, jwt.MapClaims{})
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, claims)
}

// POST /auth/refresh
func (h *Handler) HandleRefresh(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	token, err := IssueToken(userID, h.jwtSecret)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"token": token})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
