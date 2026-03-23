package main

import (
	"context"
	"database/sql"
	"net/http"
	"os"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/openwhats/server/internal/auth"
	"github.com/openwhats/server/internal/calls"
	"github.com/openwhats/server/internal/keyserver"
	"github.com/openwhats/server/internal/media"
	"github.com/openwhats/server/internal/message"
	"github.com/openwhats/server/internal/push"
	"github.com/openwhats/server/internal/relay"
	"github.com/openwhats/server/internal/user"
	"go.uber.org/zap"
)

func buildRouter(db *sql.DB, logger *zap.Logger) http.Handler {
	jwtSecret := os.Getenv("JWT_SECRET")
	bundleIDs := os.Getenv("APPLE_BUNDLE_IDS")

	// AWS S3 client
	s3Client := newS3Client(logger)
	s3Bucket := os.Getenv("AWS_S3_BUCKET")

	userRepo := user.NewRepository(db)
	keyRepo := keyserver.NewRepository(db)

	hub := relay.NewHub(logger)
	go hub.Run()

	pusher := push.NewSender(logger)

	authHandler := auth.NewHandler(userRepo, jwtSecret, bundleIDs, logger)
	userHandler := user.NewHandler(userRepo, logger)
	keyHandler := keyserver.NewHandler(keyRepo, userRepo, logger)
	wsHandler := relay.NewHandler(hub, db, logger)
	msgHandler := message.NewHandler(db, hub, pusher, logger)
	mediaHandler := media.NewHandler(db, s3Client, s3Bucket, logger)
	callsHandler := calls.NewHandler(logger)

	authMW := auth.Middleware(jwtSecret)

	mux := http.NewServeMux()

	// Public
	mux.HandleFunc("GET /health", handleHealth(db))
	mux.HandleFunc("POST /auth/apple", authHandler.HandleAppleAuth)
	mux.HandleFunc("POST /auth/debug-token", authHandler.HandleDebugToken)

	// Authenticated
	mux.Handle("POST /auth/refresh", authMW(http.HandlerFunc(authHandler.HandleRefresh)))

	mux.Handle("POST /users/register", authMW(http.HandlerFunc(userHandler.HandleRegister)))
	mux.Handle("GET /users/me", authMW(http.HandlerFunc(userHandler.HandleGetMe)))
	mux.Handle("PATCH /users/me", authMW(http.HandlerFunc(userHandler.HandleUpdateMe)))
	mux.Handle("GET /users/search", authMW(http.HandlerFunc(userHandler.HandleSearch)))
	mux.Handle("GET /users/handles/check", authMW(http.HandlerFunc(userHandler.HandleCheckHandle)))

	mux.Handle("POST /devices/register", authMW(http.HandlerFunc(userHandler.HandleRegisterDevice)))
	mux.Handle("PATCH /devices/me", authMW(http.HandlerFunc(userHandler.HandleUpdateDevice)))

	// WebSocket relay
	mux.Handle("GET /ws", authMW(http.HandlerFunc(wsHandler.ServeWS)))

	// Messaging
	mux.Handle("POST /messages/send", authMW(http.HandlerFunc(msgHandler.HandleSend)))
	mux.Handle("GET /messages/pending", authMW(http.HandlerFunc(msgHandler.HandleGetPending)))
	mux.Handle("POST /messages/ack", authMW(http.HandlerFunc(msgHandler.HandleAck)))

	// Calls (TURN credentials)
	mux.Handle("GET /calls/turn-credentials", authMW(http.HandlerFunc(callsHandler.HandleTURNCredentials)))

	// Media
	mux.Handle("POST /media/upload-url", authMW(http.HandlerFunc(mediaHandler.HandleUploadURL)))
	mux.Handle("POST /media/confirm", authMW(http.HandlerFunc(mediaHandler.HandleConfirm)))
	mux.Handle("GET /media/download-url/{key}", authMW(http.HandlerFunc(mediaHandler.HandleDownloadURL)))

	// Key server
	mux.Handle("POST /keys/bundle", authMW(http.HandlerFunc(keyHandler.HandleUploadBundle)))
	mux.Handle("PUT /keys/signed-prekey", authMW(http.HandlerFunc(keyHandler.HandleRotateSignedPreKey)))
	mux.Handle("POST /keys/one-time-prekeys", authMW(http.HandlerFunc(keyHandler.HandleReplenishOTPKs)))
	mux.Handle("GET /keys/{user_id}", authMW(http.HandlerFunc(keyHandler.HandleFetchBundles)))
	mux.Handle("GET /keys/{user_id}/count", authMW(http.HandlerFunc(keyHandler.HandleCountOTPKs)))
	mux.Handle("GET /devices", authMW(http.HandlerFunc(userHandler.HandleListDevices)))
	mux.Handle("DELETE /devices/{device_id}", authMW(http.HandlerFunc(userHandler.HandleDeleteDevice)))

	return withMiddleware(mux, logger)
}

func newS3Client(logger *zap.Logger) *s3.Client {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}
	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")

	var opts []func(*awsconfig.LoadOptions) error
	opts = append(opts, awsconfig.WithRegion(region))
	if accessKey != "" && secretKey != "" {
		opts = append(opts, awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
		))
	}
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(), opts...)
	if err != nil {
		logger.Warn("AWS config load failed — media endpoints disabled", zap.Error(err))
	}
	return s3.NewFromConfig(cfg)
}

func handleHealth(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		if err := db.PingContext(ctx); err != nil {
			http.Error(w, `{"status":"unhealthy","db":"down"}`, http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok","db":"up"}`))
	}
}

func withMiddleware(next http.Handler, logger *zap.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		w.Header().Set("Content-Type", "application/json")

		// CORS for local development
		origin := r.Header.Get("Origin")
		if origin != "" && isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Device-ID")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
		logger.Info("request",
			zap.String("method", r.Method),
			zap.String("path", r.URL.Path),
			zap.Duration("duration", time.Since(start)),
		)
	})
}

func isAllowedOrigin(origin string) bool {
	allowed := strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",")
	for _, a := range allowed {
		if strings.TrimSpace(a) == origin {
			return true
		}
	}
	return false
}
