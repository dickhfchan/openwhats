package keyserver

import (
	"encoding/json"
	"net/http"

	"github.com/openwhats/server/internal/ctxkey"
	"github.com/openwhats/server/internal/user"
	"go.uber.org/zap"
)

const minOTPKThreshold = 20 // client should replenish when below this

type Handler struct {
	repo      *Repository
	userRepo  *user.Repository
	logger    *zap.Logger
}

func NewHandler(repo *Repository, userRepo *user.Repository, logger *zap.Logger) *Handler {
	return &Handler{repo: repo, userRepo: userRepo, logger: logger}
}

type uploadBundleRequest struct {
	IdentityKey string `json:"identity_key"` // base64url
	SignedPreKey struct {
		KeyID     int    `json:"key_id"`
		PublicKey string `json:"public_key"` // base64url
		Signature string `json:"signature"`  // base64url
	} `json:"signed_pre_key"`
	OneTimePreKeys []struct {
		KeyID     int    `json:"key_id"`
		PublicKey string `json:"public_key"` // base64url
	} `json:"one_time_pre_keys"`
}

// POST /keys/bundle — upload initial key bundle for the caller's device
func (h *Handler) HandleUploadBundle(w http.ResponseWriter, r *http.Request) {
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}

	var req uploadBundleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid json"))
		return
	}

	ik, err := decodeBase64(req.IdentityKey)
	if err != nil || len(ik) != 32 {
		writeJSON(w, http.StatusBadRequest, errResp("identity_key must be 32-byte base64url"))
		return
	}
	spkPub, err := decodeBase64(req.SignedPreKey.PublicKey)
	if err != nil || len(spkPub) != 32 {
		writeJSON(w, http.StatusBadRequest, errResp("signed_pre_key.public_key must be 32-byte base64url"))
		return
	}
	spkSig, err := decodeBase64(req.SignedPreKey.Signature)
	if err != nil || len(spkSig) != 64 {
		writeJSON(w, http.StatusBadRequest, errResp("signed_pre_key.signature must be 64-byte base64url"))
		return
	}
	if len(req.OneTimePreKeys) == 0 {
		writeJSON(w, http.StatusBadRequest, errResp("one_time_pre_keys required"))
		return
	}

	otpks := make([]OTPKUpload, 0, len(req.OneTimePreKeys))
	for _, k := range req.OneTimePreKeys {
		pub, err := decodeBase64(k.PublicKey)
		if err != nil || len(pub) != 32 {
			writeJSON(w, http.StatusBadRequest, errResp("each one_time_pre_key must be 32-byte base64url"))
			return
		}
		otpks = append(otpks, OTPKUpload{KeyID: k.KeyID, PublicKey: pub})
	}

	if err := h.repo.UpsertIdentityKey(r.Context(), deviceID, ik); err != nil {
		h.logger.Error("upsert identity key", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	if err := h.repo.UpsertSignedPreKey(r.Context(), deviceID, req.SignedPreKey.KeyID, spkPub, spkSig); err != nil {
		h.logger.Error("upsert signed pre-key", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	if err := h.repo.InsertOneTimePreKeys(r.Context(), deviceID, otpks); err != nil {
		h.logger.Error("insert otpks", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"uploaded": len(otpks)})
}

// PUT /keys/signed-prekey — rotate signed pre-key
func (h *Handler) HandleRotateSignedPreKey(w http.ResponseWriter, r *http.Request) {
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}

	var req struct {
		KeyID     int    `json:"key_id"`
		PublicKey string `json:"public_key"`
		Signature string `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid json"))
		return
	}

	pub, _ := decodeBase64(req.PublicKey)
	sig, _ := decodeBase64(req.Signature)
	if len(pub) != 32 || len(sig) != 64 {
		writeJSON(w, http.StatusBadRequest, errResp("invalid key or signature size"))
		return
	}

	if err := h.repo.UpsertSignedPreKey(r.Context(), deviceID, req.KeyID, pub, sig); err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /keys/one-time-prekeys — replenish OTPKs
func (h *Handler) HandleReplenishOTPKs(w http.ResponseWriter, r *http.Request) {
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}

	var req struct {
		Keys []struct {
			KeyID     int    `json:"key_id"`
			PublicKey string `json:"public_key"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Keys) == 0 {
		writeJSON(w, http.StatusBadRequest, errResp("keys array required"))
		return
	}

	otpks := make([]OTPKUpload, 0, len(req.Keys))
	for _, k := range req.Keys {
		pub, err := decodeBase64(k.PublicKey)
		if err != nil || len(pub) != 32 {
			writeJSON(w, http.StatusBadRequest, errResp("each key must be 32-byte base64url"))
			return
		}
		otpks = append(otpks, OTPKUpload{KeyID: k.KeyID, PublicKey: pub})
	}

	if err := h.repo.InsertOneTimePreKeys(r.Context(), deviceID, otpks); err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"uploaded": len(otpks)})
}

// GET /keys/{user_id} — fetch pre-key bundles for all devices of the target user
func (h *Handler) HandleFetchBundles(w http.ResponseWriter, r *http.Request) {
	targetUserID := r.PathValue("user_id")
	if targetUserID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("user_id required"))
		return
	}

	// Verify target user exists
	if _, err := h.userRepo.GetByID(r.Context(), targetUserID); err != nil {
		writeJSON(w, http.StatusNotFound, errResp("user not found"))
		return
	}

	bundles, err := h.repo.FetchBundlesForUser(r.Context(), targetUserID)
	if err != nil {
		h.logger.Error("fetch bundles", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	if len(bundles) == 0 {
		writeJSON(w, http.StatusNotFound, errResp("no key bundles found for user"))
		return
	}

	type bundleResponse struct {
		DeviceID        string  `json:"device_id"`
		DeviceType      string  `json:"device_type"`
		IdentityKey     string  `json:"identity_key"`
		SignedPreKeyID  int     `json:"signed_pre_key_id"`
		SignedPreKey    string  `json:"signed_pre_key"`
		SignedPreKeySig string  `json:"signed_pre_key_sig"`
		OneTimePreKeyID *int    `json:"one_time_pre_key_id,omitempty"`
		OneTimePreKey   *string `json:"one_time_pre_key,omitempty"`
	}

	resp := make([]bundleResponse, len(bundles))
	for i, b := range bundles {
		resp[i] = bundleResponse{
			DeviceID:        b.DeviceID,
			DeviceType:      b.DeviceType,
			IdentityKey:     encodeBase64(b.IdentityKey),
			SignedPreKeyID:  b.SignedPreKeyID,
			SignedPreKey:    encodeBase64(b.SignedPreKey),
			SignedPreKeySig: encodeBase64(b.SignedPreKeySig),
		}
		if b.OneTimePreKeyID != nil {
			id := *b.OneTimePreKeyID
			resp[i].OneTimePreKeyID = &id
			s := encodeBase64(b.OneTimePreKey)
			resp[i].OneTimePreKey = &s
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{"bundles": resp})
}

// GET /keys/{user_id}/count — OTPK count per device (for own devices)
func (h *Handler) HandleCountOTPKs(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	targetUserID := r.PathValue("user_id")
	if targetUserID != userID {
		writeJSON(w, http.StatusForbidden, errResp("can only check own key counts"))
		return
	}

	devices, err := h.userRepo.GetDevicesByUserID(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	type deviceCount struct {
		DeviceID   string `json:"device_id"`
		DeviceType string `json:"device_type"`
		Count      int    `json:"count"`
		NeedsRefill bool  `json:"needs_refill"`
	}

	counts := make([]deviceCount, 0, len(devices))
	for _, d := range devices {
		n, err := h.repo.CountOneTimePreKeys(r.Context(), d.ID)
		if err != nil {
			continue
		}
		counts = append(counts, deviceCount{
			DeviceID:    d.ID,
			DeviceType:  d.DeviceType,
			Count:       n,
			NeedsRefill: n < minOTPKThreshold,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": counts})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func errResp(msg string) map[string]string {
	return map[string]string{"error": msg}
}
