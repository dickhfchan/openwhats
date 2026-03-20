package relay

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
	"github.com/openwhats/server/internal/ctxkey"
	"go.uber.org/zap"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // origin validated at auth layer
	},
}

// Handler upgrades HTTP connections to WebSocket and registers clients with the Hub.
type Handler struct {
	hub    *Hub
	db     *sql.DB
	logger *zap.Logger
}

func NewHandler(hub *Hub, db *sql.DB, logger *zap.Logger) *Handler {
	return &Handler{hub: hub, db: db, logger: logger}
}

// ServeWS handles GET /ws — upgrades to WebSocket.
// Authentication: JWT in Authorization header + X-Device-ID header.
func (h *Handler) ServeWS(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())
	deviceID := ctxkey.GetDeviceID(r.Context())
	if deviceID == "" {
		http.Error(w, `{"error":"X-Device-ID header required"}`, http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Warn("ws upgrade failed", zap.Error(err))
		return
	}

	client := &Client{
		hub:      h.hub,
		conn:     conn,
		send:     make(chan []byte, 256),
		userID:   userID,
		deviceID: deviceID,
		logger:   h.logger,
	}

	// Wire up ACK handler to delete envelopes from DB
	client.onAck = func(ids []string) {
		h.deleteEnvelopes(context.Background(), ids, deviceID)
		h.logger.Debug("acked envelopes", zap.Strings("ids", ids), zap.String("device", deviceID))
	}

	// Wire up receipt handler to route receipts back to sender
	client.onReceipt = func(msgType WSMessageType, receipt ReceiptPayload) {
		frame, _ := MarshalFrame(msgType, receipt)
		// Route receipt to sender's device
		h.hub.Send(receipt.SenderDeviceID, frame)
	}

	// Wire up call signal relay
	client.onCallSignal = func(sig CallSignalPayload) {
		frame, _ := MarshalFrame(TypeCallSignal, sig)
		if sig.ToDeviceID != "" {
			h.hub.Send(sig.ToDeviceID, frame)
		} else {
			h.hub.SendToUser(sig.ToUserID, frame)
		}
	}

	h.hub.register <- client

	// Send CONNECTED frame
	connected, _ := MarshalFrame(TypeConnected, nil)
	client.send <- connected

	// Flush any queued offline messages
	go h.flushPending(client)

	go client.WritePump()
	client.ReadPump() // blocks until disconnect
}

// flushPending sends all queued envelopes for this device over WebSocket.
func (h *Handler) flushPending(client *Client) {
	rows, err := h.db.QueryContext(context.Background(),
		`SELECT id, sender_user_id, sender_device_id, payload, created_at
		 FROM message_envelopes
		 WHERE recipient_device_id = $1
		 ORDER BY created_at
		 LIMIT 500`,
		client.deviceID,
	)
	if err != nil {
		h.logger.Error("flush pending query", zap.Error(err))
		return
	}
	defer rows.Close()

	for rows.Next() {
		var env EnvelopePayload
		var createdAt time.Time
		if err := rows.Scan(&env.ID, &env.SenderUserID, &env.SenderDeviceID,
			&env.Payload, &createdAt); err != nil {
			continue
		}
		env.Timestamp = createdAt.UnixMilli()
		env.RecipientDeviceID = client.deviceID

		frame, err := MarshalFrame(TypeEnvelope, env)
		if err != nil {
			continue
		}
		select {
		case client.send <- frame:
		default:
		}
	}
}

func (h *Handler) deleteEnvelopes(ctx context.Context, ids []string, deviceID string) {
	if len(ids) == 0 {
		return
	}
	// Build parameterized query for the id list
	args := make([]any, len(ids)+1)
	args[0] = deviceID
	placeholders := make([]byte, 0, len(ids)*5)
	for i, id := range ids {
		if i > 0 {
			placeholders = append(placeholders, ',')
		}
		placeholders = append(placeholders, '$')
		args[i+1] = id
		placeholders = append(placeholders, []byte(itoa(i+2))...)
	}
	query := "DELETE FROM message_envelopes WHERE recipient_device_id = $1 AND id IN (" +
		string(placeholders) + ")"
	h.db.ExecContext(ctx, query, args...)
}

func itoa(n int) string {
	if n < 10 {
		return string(rune('0' + n))
	}
	return string(rune('0'+n/10)) + string(rune('0'+n%10))
}
