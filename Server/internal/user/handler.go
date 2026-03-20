package user

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	"github.com/openwhats/server/internal/ctxkey"
	"go.uber.org/zap"
)

var handleRe = regexp.MustCompile(`^[a-z0-9_]{3,20}$`)

type Handler struct {
	repo   *Repository
	logger *zap.Logger
}

func NewHandler(repo *Repository, logger *zap.Logger) *Handler {
	return &Handler{repo: repo, logger: logger}
}

// POST /users/register — set handle + display name (onboarding)
func (h *Handler) HandleRegister(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())

	var body struct {
		Handle      string `json:"handle"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid json"))
		return
	}

	handle := strings.ToLower(strings.TrimSpace(body.Handle))
	displayName := strings.TrimSpace(body.DisplayName)

	if !handleRe.MatchString(handle) {
		writeJSON(w, http.StatusBadRequest, errResp("handle must be 3-20 chars: lowercase letters, digits, underscore"))
		return
	}
	if displayName == "" || len(displayName) > 64 {
		writeJSON(w, http.StatusBadRequest, errResp("display_name required (max 64 chars)"))
		return
	}

	u, err := h.repo.SetHandleAndName(r.Context(), userID, handle, displayName)
	if err == ErrHandleTaken {
		writeJSON(w, http.StatusConflict, errResp("handle already taken"))
		return
	}
	if err != nil {
		h.logger.Error("set handle", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	writeJSON(w, http.StatusOK, u)
}

// GET /users/me
func (h *Handler) HandleGetMe(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	u, err := h.repo.GetByID(r.Context(), userID)
	if err == ErrNotFound {
		writeJSON(w, http.StatusNotFound, errResp("user not found"))
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, u)
}

// PATCH /users/me
func (h *Handler) HandleUpdateMe(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	var body struct {
		DisplayName string  `json:"display_name"`
		AvatarURL   *string `json:"avatar_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid json"))
		return
	}
	displayName := strings.TrimSpace(body.DisplayName)
	if displayName == "" {
		writeJSON(w, http.StatusBadRequest, errResp("display_name required"))
		return
	}
	u, err := h.repo.Update(r.Context(), userID, displayName, body.AvatarURL)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, u)
}

// GET /users/search?handle=foo
func (h *Handler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	handle := strings.TrimSpace(r.URL.Query().Get("handle"))
	if handle == "" {
		writeJSON(w, http.StatusBadRequest, errResp("handle query param required"))
		return
	}
	u, err := h.repo.GetByHandle(r.Context(), handle)
	if err == ErrNotFound {
		writeJSON(w, http.StatusNotFound, errResp("user not found"))
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, u)
}

// GET /users/handles/check?handle=foo — availability check (debounced from client)
func (h *Handler) HandleCheckHandle(w http.ResponseWriter, r *http.Request) {
	handle := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("handle")))
	if !handleRe.MatchString(handle) {
		writeJSON(w, http.StatusOK, map[string]any{"handle": handle, "available": false, "reason": "invalid format"})
		return
	}
	exists, err := h.repo.HandleExists(r.Context(), handle)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"handle": handle, "available": !exists})
}

// POST /devices/register
func (h *Handler) HandleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())

	var body struct {
		DeviceType string  `json:"device_type"`
		APNSToken  *string `json:"apns_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid json"))
		return
	}
	if body.DeviceType != "phone" && body.DeviceType != "desktop" {
		writeJSON(w, http.StatusBadRequest, errResp("device_type must be phone or desktop"))
		return
	}

	d, err := h.repo.CreateDevice(r.Context(), userID, body.DeviceType, body.APNSToken)
	if err != nil {
		h.logger.Error("register device", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

// PATCH /devices/me — update APNs token for the calling device
func (h *Handler) HandleUpdateDevice(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}
	var body struct {
		APNSToken string `json:"apns_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.APNSToken == "" {
		writeJSON(w, http.StatusBadRequest, errResp("apns_token required"))
		return
	}
	if err := h.repo.UpdateAPNSToken(r.Context(), deviceID, userID, body.APNSToken); err == ErrNotFound {
		writeJSON(w, http.StatusNotFound, errResp("device not found"))
		return
	} else if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /devices — list own devices
func (h *Handler) HandleListDevices(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	devices, err := h.repo.GetDevicesByUserID(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

// DELETE /devices/{device_id}
func (h *Handler) HandleDeleteDevice(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	deviceID := r.PathValue("device_id")
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("device_id required"))
		return
	}
	if err := h.repo.DeleteDevice(r.Context(), deviceID, userID); err == ErrNotFound {
		writeJSON(w, http.StatusNotFound, errResp("device not found"))
		return
	} else if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func errResp(msg string) map[string]string {
	return map[string]string{"error": msg}
}
