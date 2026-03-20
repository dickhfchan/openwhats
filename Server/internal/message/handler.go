package message

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/openwhats/server/internal/ctxkey"
	"github.com/openwhats/server/internal/push"
	"github.com/openwhats/server/internal/ratelimit"
	"github.com/openwhats/server/internal/relay"
	"go.uber.org/zap"
)

type Handler struct {
	db      *sql.DB
	hub     *relay.Hub
	pusher  *push.Sender
	limiter *ratelimit.Limiter
	logger  *zap.Logger
}

func NewHandler(db *sql.DB, hub *relay.Hub, pusher *push.Sender, logger *zap.Logger) *Handler {
	return &Handler{
		db:      db,
		hub:     hub,
		pusher:  pusher,
		limiter: ratelimit.NewLimiter(1.0, 5.0), // 1/sec, burst 5
		logger:  logger,
	}
}

// POST /messages/send
// Body: {"envelopes": [{recipient_user_id, recipient_device_id, payload (base64)}]}
// The server never inspects payload content — purely routes ciphertext.
func (h *Handler) HandleSend(w http.ResponseWriter, r *http.Request) {
	senderUserID := ctxkey.GetUserID(r.Context())
	senderDeviceID := ctxkey.GetDeviceID(r.Context())
	if senderDeviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}

	// Rate limit: 1 msg/sec per user, burst 5
	if !h.limiter.Allow(senderUserID, 1) {
		w.Header().Set("Retry-After", "1")
		writeJSON(w, http.StatusTooManyRequests, errResp("rate limit exceeded"))
		return
	}

	var body struct {
		Envelopes []struct {
			RecipientUserID   string `json:"recipient_user_id"`
			RecipientDeviceID string `json:"recipient_device_id"`
			Payload           []byte `json:"payload"`
		} `json:"envelopes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body.Envelopes) == 0 {
		writeJSON(w, http.StatusBadRequest, errResp("envelopes array required"))
		return
	}
	if len(body.Envelopes) > 10 {
		writeJSON(w, http.StatusBadRequest, errResp("max 10 envelopes per request"))
		return
	}

	envelopeIDs := make([]string, 0, len(body.Envelopes))

	for _, e := range body.Envelopes {
		if len(e.Payload) == 0 || e.RecipientDeviceID == "" {
			writeJSON(w, http.StatusBadRequest, errResp("each envelope needs recipient_device_id and payload"))
			return
		}

		// Persist envelope
		envID, err := h.storeEnvelope(r.Context(), senderUserID, senderDeviceID, e.RecipientDeviceID, e.Payload)
		if err != nil {
			if isForeignKeyViolation(err) {
				writeJSON(w, http.StatusNotFound, errResp("recipient device not registered"))
				return
			}
			h.logger.Error("store envelope", zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
			return
		}
		envelopeIDs = append(envelopeIDs, envID)

		// Try WebSocket delivery
		env := relay.EnvelopePayload{
			ID:                envID,
			SenderUserID:      senderUserID,
			SenderDeviceID:    senderDeviceID,
			RecipientDeviceID: e.RecipientDeviceID,
			Payload:           e.Payload,
			Timestamp:         time.Now().UnixMilli(),
		}
		frame, _ := relay.MarshalFrame(relay.TypeEnvelope, env)

		if h.hub.Send(e.RecipientDeviceID, frame) {
			// Delivered live — but keep in DB until ACK removes it
		} else {
			// Offline — send APNs push
			go h.sendPush(e.RecipientUserID, e.RecipientDeviceID, envID)
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{"envelope_ids": envelopeIDs})
}

// GET /messages/pending — fetch all queued envelopes for this device
func (h *Handler) HandleGetPending(w http.ResponseWriter, r *http.Request) {
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, errResp("X-Device-ID header required"))
		return
	}

	rows, err := h.db.QueryContext(r.Context(),
		`SELECT id, sender_user_id, sender_device_id, payload, created_at
		 FROM message_envelopes
		 WHERE recipient_device_id = $1
		 ORDER BY created_at
		 LIMIT 500`,
		deviceID,
	)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	defer rows.Close()

	type envResp struct {
		ID             string `json:"id"`
		SenderUserID   string `json:"sender_user_id"`
		SenderDeviceID string `json:"sender_device_id"`
		Payload        []byte `json:"payload"`
		Timestamp      int64  `json:"timestamp"`
	}

	envelopes := make([]envResp, 0)
	for rows.Next() {
		var e envResp
		var createdAt time.Time
		if err := rows.Scan(&e.ID, &e.SenderUserID, &e.SenderDeviceID, &e.Payload, &createdAt); err != nil {
			continue
		}
		e.Timestamp = createdAt.UnixMilli()
		envelopes = append(envelopes, e)
	}

	writeJSON(w, http.StatusOK, map[string]any{"envelopes": envelopes})
}

// POST /messages/ack — delete acknowledged envelopes
func (h *Handler) HandleAck(w http.ResponseWriter, r *http.Request) {
	deviceID := ctxkey.GetDeviceID(r.Context())
	var body struct {
		EnvelopeIDs []string `json:"envelope_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body.EnvelopeIDs) == 0 {
		writeJSON(w, http.StatusBadRequest, errResp("envelope_ids required"))
		return
	}

	deleted, err := h.deleteEnvelopes(r.Context(), body.EnvelopeIDs, deviceID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": deleted})
}

// storeEnvelope persists a message envelope to the DB and returns its UUID.
func (h *Handler) storeEnvelope(ctx context.Context, senderUserID, senderDeviceID, recipientDeviceID string, payload []byte) (string, error) {
	var id string
	err := h.db.QueryRowContext(ctx,
		`INSERT INTO message_envelopes (sender_user_id, sender_device_id, recipient_device_id, payload)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		senderUserID, senderDeviceID, recipientDeviceID, payload,
	).Scan(&id)
	return id, err
}

func (h *Handler) deleteEnvelopes(ctx context.Context, ids []string, deviceID string) (int64, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	// Build query with placeholders
	query := fmt.Sprintf(
		`DELETE FROM message_envelopes WHERE recipient_device_id = $1 AND id = ANY($2::uuid[])`,
	)
	result, err := h.db.ExecContext(ctx, query, deviceID, ids)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}

func (h *Handler) sendPush(recipientUserID, recipientDeviceID, envelopeID string) {
	// Look up the device's APNs token
	var apnsToken *string
	err := h.db.QueryRowContext(context.Background(),
		`SELECT apns_token FROM devices WHERE id = $1`, recipientDeviceID,
	).Scan(&apnsToken)
	if err != nil || apnsToken == nil {
		return
	}

	h.pusher.Send(context.Background(), push.Notification{
		DeviceToken:    *apnsToken,
		Title:          "New message",
		Body:           "You have a new encrypted message",
		MutableContent: true, // NSE will decrypt and replace this
		CollapseID:     "msg-" + recipientDeviceID,
		Data:           map[string]any{"envelope_id": envelopeID},
	})
}

func isForeignKeyViolation(err error) bool {
	return err != nil && (strings.Contains(err.Error(), "foreign key") ||
		strings.Contains(err.Error(), "violates") ||
		strings.Contains(err.Error(), "fk_"))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func errResp(msg string) map[string]string {
	return map[string]string{"error": msg}
}
