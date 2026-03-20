package media

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/openwhats/server/internal/ctxkey"
	"go.uber.org/zap"
)

const (
	maxUploadBytes  = 32 * 1024 * 1024 // 32 MB hard limit
	putURLExpiry    = 15 * time.Minute
	getURLExpiry    = 5 * time.Minute
)

type Handler struct {
	db      *sql.DB
	s3      *s3.Client
	presign *s3.PresignClient
	bucket  string
	logger  *zap.Logger
}

func NewHandler(db *sql.DB, s3Client *s3.Client, bucket string, logger *zap.Logger) *Handler {
	return &Handler{
		db:      db,
		s3:      s3Client,
		presign: s3.NewPresignClient(s3Client),
		bucket:  bucket,
		logger:  logger,
	}
}

// POST /media/upload-url
// Body: {"mime_type": "image/jpeg", "size_bytes": 123456}
// Returns: {"object_key": "...", "upload_url": "..."}
func (h *Handler) HandleUploadURL(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())

	var body struct {
		MimeType  string `json:"mime_type"`
		SizeBytes int64  `json:"size_bytes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errResp("invalid request body"))
		return
	}
	if body.MimeType == "" {
		writeJSON(w, http.StatusBadRequest, errResp("mime_type required"))
		return
	}
	if body.SizeBytes <= 0 || body.SizeBytes > maxUploadBytes {
		writeJSON(w, http.StatusBadRequest, errResp(fmt.Sprintf("size_bytes must be 1–%d", maxUploadBytes)))
		return
	}

	// Reserve a row in media_objects (uncommitted until /confirm)
	var objectKey string
	err := h.db.QueryRowContext(r.Context(),
		`INSERT INTO media_objects (uploader_id, s3_key, mime_type, size_bytes)
		 VALUES ($1, 'pending-' || gen_random_uuid(), $2, $3)
		 RETURNING s3_key`,
		userID, body.MimeType, body.SizeBytes,
	).Scan(&objectKey)
	if err != nil {
		h.logger.Error("insert media_object", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	// Generate pre-signed PUT URL
	req, err := h.presign.PresignPutObject(r.Context(), &s3.PutObjectInput{
		Bucket:        aws.String(h.bucket),
		Key:           aws.String(objectKey),
		ContentType:   aws.String(body.MimeType),
		ContentLength: aws.Int64(body.SizeBytes),
	}, s3.WithPresignExpires(putURLExpiry))
	if err != nil {
		h.logger.Error("presign put object", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"object_key": objectKey,
		"upload_url": req.URL,
	})
}

// POST /media/confirm
// Body: {"object_key": "..."}
func (h *Handler) HandleConfirm(w http.ResponseWriter, r *http.Request) {
	userID := ctxkey.GetUserID(r.Context())

	var body struct {
		ObjectKey string `json:"object_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.ObjectKey == "" {
		writeJSON(w, http.StatusBadRequest, errResp("object_key required"))
		return
	}

	// Verify object belongs to caller and is uncommitted
	var id string
	err := h.db.QueryRowContext(r.Context(),
		`SELECT id FROM media_objects WHERE s3_key = $1 AND uploader_id = $2 AND committed_at IS NULL`,
		body.ObjectKey, userID,
	).Scan(&id)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusNotFound, errResp("object not found or already confirmed"))
		return
	}
	if err != nil {
		h.logger.Error("query media_object", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	// Verify object exists in S3
	_, err = h.s3.HeadObject(r.Context(), &s3.HeadObjectInput{
		Bucket: aws.String(h.bucket),
		Key:    aws.String(body.ObjectKey),
	})
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, errResp("object not found in storage — upload first"))
		return
	}

	// Mark as committed
	_, err = h.db.ExecContext(r.Context(),
		`UPDATE media_objects SET committed_at = now() WHERE id = $1`,
		id,
	)
	if err != nil {
		h.logger.Error("commit media_object", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "confirmed"})
}

// GET /media/download-url/{key}
func (h *Handler) HandleDownloadURL(w http.ResponseWriter, r *http.Request) {
	objectKey := r.PathValue("key")
	if objectKey == "" {
		writeJSON(w, http.StatusBadRequest, errResp("key required"))
		return
	}

	// Verify object is committed (any authenticated user can download committed objects)
	var exists bool
	err := h.db.QueryRowContext(r.Context(),
		`SELECT true FROM media_objects WHERE s3_key = $1 AND committed_at IS NOT NULL`,
		objectKey,
	).Scan(&exists)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusNotFound, errResp("object not found"))
		return
	}
	if err != nil {
		h.logger.Error("query media_object for download", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	// Generate pre-signed GET URL
	req, err := h.presign.PresignGetObject(r.Context(), &s3.GetObjectInput{
		Bucket: aws.String(h.bucket),
		Key:    aws.String(objectKey),
	}, func(o *s3.PresignOptions) {
		o.Expires = getURLExpiry
	})
	if err != nil {
		h.logger.Error("presign get object", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errResp("internal error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"download_url": req.URL,
		"expires_in":   fmt.Sprintf("%d", int(getURLExpiry.Seconds())),
	})
}

// cleanupUncommitted removes abandoned upload rows older than 1 hour.
// Called periodically from main.
func CleanupUncommitted(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx,
		`DELETE FROM media_objects WHERE committed_at IS NULL AND created_at < now() - interval '1 hour'`,
	)
	return err
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func errResp(msg string) map[string]string {
	return map[string]string{"error": msg}
}
