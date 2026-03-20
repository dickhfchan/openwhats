package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"go.uber.org/zap"
)

func main() {
	// Load .env — check project root first, then current directory
	if err := godotenv.Load("../.env"); err != nil {
		_ = godotenv.Load(".env")
	}

	logger, _ := zap.NewProduction()
	defer logger.Sync()

	db, err := connectDB(logger)
	if err != nil {
		logger.Fatal("failed to connect to database", zap.Error(err))
	}
	defer db.Close()

	if err := runMigrations(db, logger); err != nil {
		logger.Fatal("failed to run migrations", zap.Error(err))
	}

	router := buildRouter(db, logger)

	// Background job: purge stale envelopes (> 30 days)
	go func() {
		ticker := time.NewTicker(24 * time.Hour)
		for range ticker.C {
			res, err := db.ExecContext(context.Background(),
				`DELETE FROM message_envelopes WHERE created_at < now() - interval '30 days'`)
			if err == nil {
				n, _ := res.RowsAffected()
				if n > 0 {
					logger.Info("purged stale envelopes", zap.Int64("count", n))
				}
			}
		}
	}()

	port := envOrDefault("SERVER_PORT", "8080")
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		logger.Info("server starting", zap.String("port", port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Info("shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("forced shutdown", zap.Error(err))
	}
	logger.Info("server stopped")
}

func connectDB(logger *zap.Logger) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		envOrDefault("POSTGRES_HOST", "localhost"),
		envOrDefault("POSTGRES_PORT", "5432"),
		envOrDefault("POSTGRES_USER", "vibiz_user"),
		envOrDefault("POSTGRES_PASSWORD", ""),
		envOrDefault("POSTGRES_DB", "openwhats"),
		envOrDefault("POSTGRES_SSLMODE", "disable"),
	)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("ping failed: %w", err)
	}

	logger.Info("database connected",
		zap.String("host", envOrDefault("POSTGRES_HOST", "localhost")),
		zap.String("db", envOrDefault("POSTGRES_DB", "openwhats")),
	)
	return db, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
