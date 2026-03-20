package relay

import "encoding/json"

// WSMessageType defines the type of a WebSocket frame.
type WSMessageType string

const (
	TypeEnvelope         WSMessageType = "ENVELOPE"
	TypeDeliveryReceipt  WSMessageType = "DELIVERY_RECEIPT"
	TypeReadReceipt      WSMessageType = "READ_RECEIPT"
	TypeCallSignal       WSMessageType = "CALL_SIGNAL"
	TypePing             WSMessageType = "PING"
	TypePong             WSMessageType = "PONG"
	TypeAck              WSMessageType = "ACK"
	TypeConnected        WSMessageType = "CONNECTED"
)

// WSFrame is the top-level envelope for all WebSocket messages.
type WSFrame struct {
	Type WSMessageType   `json:"type"`
	Data json.RawMessage `json:"data,omitempty"`
}

// EnvelopePayload is a Signal Protocol message envelope routed through the server.
// The server sees only ciphertext — never plaintext.
type EnvelopePayload struct {
	ID                string `json:"id"`
	SenderUserID      string `json:"sender_user_id"`
	SenderDeviceID    string `json:"sender_device_id"`
	RecipientDeviceID string `json:"recipient_device_id"`
	Payload           []byte `json:"payload"` // encrypted bytes, opaque to server
	Timestamp         int64  `json:"timestamp"`
}

// ReceiptPayload is sent by the recipient to acknowledge delivery or read status.
type ReceiptPayload struct {
	EnvelopeID    string `json:"envelope_id"`
	SenderUserID  string `json:"sender_user_id"`
	SenderDeviceID string `json:"sender_device_id"`
	Timestamp     int64  `json:"timestamp"`
}

// AckPayload confirms receipt of envelope IDs so server can delete them.
type AckPayload struct {
	EnvelopeIDs []string `json:"envelope_ids"`
}

// CallSignalPayload is a WebRTC signaling message relayed peer-to-peer through the server.
// Server never inspects SignalData — it's opaque JSON (SDP offer/answer or ICE candidate).
type CallSignalPayload struct {
	CallID       string          `json:"call_id"`
	FromUserID   string          `json:"from_user_id"`
	FromDeviceID string          `json:"from_device_id"`
	ToUserID     string          `json:"to_user_id"`
	ToDeviceID   string          `json:"to_device_id,omitempty"` // empty = all devices of ToUserID
	SignalType   string          `json:"signal_type"`            // offer|answer|ice_candidate|hangup|ringing|busy
	SignalData   json.RawMessage `json:"signal_data,omitempty"`
}

// MarshalFrame serialises a typed WebSocket frame.
func MarshalFrame(msgType WSMessageType, data any) ([]byte, error) {
	raw, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}
	return json.Marshal(WSFrame{Type: msgType, Data: raw})
}
