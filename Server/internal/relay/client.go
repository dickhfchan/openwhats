package relay

import (
	"encoding/json"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = 30 * time.Second
	maxMessageSize = 65536 // 64 KB max per frame
)

// Client represents a single WebSocket connection.
type Client struct {
	hub      *Hub
	conn     *websocket.Conn
	send     chan []byte
	userID   string
	deviceID string
	logger   *zap.Logger

	// Called when client sends ACK, delivery/read receipts, or call signals
	onAck        func(envelopeIDs []string)
	onReceipt    func(msgType WSMessageType, payload ReceiptPayload)
	onCallSignal func(signal CallSignalPayload)
}

// ReadPump reads frames from the WebSocket and dispatches them.
// Must run in its own goroutine.
func (c *Client) ReadPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				c.logger.Warn("unexpected ws close", zap.Error(err))
			}
			break
		}

		var frame WSFrame
		if err := json.Unmarshal(raw, &frame); err != nil {
			continue
		}

		switch frame.Type {
		case TypePing:
			pong, _ := MarshalFrame(TypePong, nil)
			c.send <- pong

		case TypeAck:
			var ack AckPayload
			if err := json.Unmarshal(frame.Data, &ack); err == nil && c.onAck != nil {
				c.onAck(ack.EnvelopeIDs)
			}

		case TypeDeliveryReceipt, TypeReadReceipt:
			var receipt ReceiptPayload
			if err := json.Unmarshal(frame.Data, &receipt); err == nil && c.onReceipt != nil {
				c.onReceipt(frame.Type, receipt)
			}

		case TypeCallSignal:
			var sig CallSignalPayload
			if err := json.Unmarshal(frame.Data, &sig); err == nil && c.onCallSignal != nil {
				sig.FromUserID = c.userID
				sig.FromDeviceID = c.deviceID
				c.onCallSignal(sig)
			}
		}
	}
}

// WritePump drains the send channel to the WebSocket.
// Must run in its own goroutine.
func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
