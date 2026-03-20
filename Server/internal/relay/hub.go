package relay

import (
	"sync"

	"go.uber.org/zap"
)

// Hub maintains the set of active WebSocket clients and routes messages between them.
type Hub struct {
	mu      sync.RWMutex
	clients map[string]map[string]*Client // userID -> deviceID -> *Client

	register   chan *Client
	unregister chan *Client
	route      chan routeMsg

	logger *zap.Logger
}

type routeMsg struct {
	deviceID string
	data     []byte
}

func NewHub(logger *zap.Logger) *Hub {
	return &Hub{
		clients:    make(map[string]map[string]*Client),
		register:   make(chan *Client, 32),
		unregister: make(chan *Client, 32),
		route:      make(chan routeMsg, 512),
		logger:     logger,
	}
}

// Run starts the hub event loop. Call in a goroutine.
func (h *Hub) Run() {
	for {
		select {
		case c := <-h.register:
			h.mu.Lock()
			if h.clients[c.userID] == nil {
				h.clients[c.userID] = make(map[string]*Client)
			}
			h.clients[c.userID][c.deviceID] = c
			h.mu.Unlock()
			h.logger.Info("client connected",
				zap.String("user_id", c.userID),
				zap.String("device_id", c.deviceID))

		case c := <-h.unregister:
			h.mu.Lock()
			if devices, ok := h.clients[c.userID]; ok {
				delete(devices, c.deviceID)
				if len(devices) == 0 {
					delete(h.clients, c.userID)
				}
			}
			h.mu.Unlock()
			h.logger.Info("client disconnected",
				zap.String("user_id", c.userID),
				zap.String("device_id", c.deviceID))

		case msg := <-h.route:
			h.mu.RLock()
			// route by deviceID (search across all users)
			delivered := false
			for _, devices := range h.clients {
				if client, ok := devices[msg.deviceID]; ok {
					select {
					case client.send <- msg.data:
						delivered = true
					default:
						// client send buffer full; will be picked up via pending on reconnect
					}
					break
				}
			}
			h.mu.RUnlock()
			_ = delivered
		}
	}
}

// Send routes a raw frame to a specific device. Non-blocking; returns false if device is offline.
func (h *Hub) Send(deviceID string, data []byte) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, devices := range h.clients {
		if client, ok := devices[deviceID]; ok {
			select {
			case client.send <- data:
				return true
			default:
				return false
			}
		}
	}
	return false
}

// SendToUser sends a raw frame to ALL online devices of the given user.
func (h *Hub) SendToUser(userID string, data []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for devID, client := range h.clients[userID] {
		select {
		case client.send <- data:
		default:
			h.logger.Warn("send buffer full", zap.String("device_id", devID))
		}
	}
}

// IsOnline reports whether a device currently has an active WebSocket connection.
func (h *Hub) IsOnline(deviceID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, devices := range h.clients {
		if _, ok := devices[deviceID]; ok {
			return true
		}
	}
	return false
}
