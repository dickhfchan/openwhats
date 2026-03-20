// Package push sends Apple Push Notifications to wake offline devices.
// Configure APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID in environment to enable real pushes.
// Without configuration, push notifications are logged but not sent (safe for development).
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"go.uber.org/zap"
)

const (
	apnsProductionHost = "https://api.push.apple.com"
	apnsSandboxHost    = "https://api.sandbox.push.apple.com"
)

// Sender sends APNs push notifications.
type Sender struct {
	bundleID string
	sandbox  bool
	logger   *zap.Logger
	enabled  bool
}

func NewSender(logger *zap.Logger) *Sender {
	bundleID := os.Getenv("APNS_BUNDLE_ID")
	if bundleID == "" {
		bundleID = "com.openwhats.app"
	}
	enabled := os.Getenv("APNS_KEY_PATH") != "" &&
		os.Getenv("APNS_KEY_ID") != "" &&
		os.Getenv("APNS_TEAM_ID") != ""

	if !enabled {
		logger.Info("APNs push disabled — set APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID to enable")
	}

	return &Sender{
		bundleID: bundleID,
		sandbox:  os.Getenv("APNS_SANDBOX") == "true",
		logger:   logger,
		enabled:  enabled,
	}
}

type Notification struct {
	DeviceToken string
	Title       string
	Body        string
	// MutableContent: true causes iOS to invoke the Notification Service Extension
	// which decrypts the message before displaying it.
	MutableContent bool
	// CollapseID: used to collapse multiple notifications (e.g., same conversation)
	CollapseID string
	// Data: extra payload accessible in the NSE
	Data map[string]any
}

func (s *Sender) Send(ctx context.Context, n Notification) error {
	if !s.enabled {
		s.logger.Info("apns push (disabled)",
			zap.String("token", maskToken(n.DeviceToken)),
			zap.String("title", n.Title))
		return nil
	}

	host := apnsProductionHost
	if s.sandbox {
		host = apnsSandboxHost
	}

	payload := buildPayload(n)
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	url := fmt.Sprintf("%s/3/device/%s", host, n.DeviceToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", s.bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-expiration", fmt.Sprintf("%d", time.Now().Add(24*time.Hour).Unix()))
	if n.CollapseID != "" {
		req.Header.Set("apns-collapse-id", n.CollapseID)
	}
	// TODO: add JWT auth header (requires loading .p8 key and signing with ES256)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("apns returned status %d", resp.StatusCode)
	}
	return nil
}

func buildPayload(n Notification) map[string]any {
	alert := map[string]any{
		"title": n.Title,
		"body":  n.Body,
	}
	aps := map[string]any{
		"alert": alert,
		"sound": "default",
	}
	if n.MutableContent {
		aps["mutable-content"] = 1
	}

	payload := map[string]any{"aps": aps}
	for k, v := range n.Data {
		payload[k] = v
	}
	return payload
}

func maskToken(token string) string {
	if len(token) <= 8 {
		return "***"
	}
	return token[:4] + "..." + token[len(token)-4:]
}
