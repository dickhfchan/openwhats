package ratelimit

import (
	"sync"
	"time"
)

// Limiter is a per-key token bucket rate limiter.
// Default: 1 token/second, burst of 5.
type Limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	rate    float64
	burst   float64
}

type bucket struct {
	tokens    float64
	lastTime  time.Time
}

func NewLimiter(ratePerSec float64, burst float64) *Limiter {
	l := &Limiter{
		buckets: make(map[string]*bucket),
		rate:    ratePerSec,
		burst:   burst,
	}
	// Periodic cleanup to avoid unbounded growth
	go l.cleanup()
	return l
}

// Allow returns true if the key is within the rate limit.
// cost is the number of tokens to consume (e.g., number of envelopes being sent).
func (l *Limiter) Allow(key string, cost float64) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{tokens: l.burst, lastTime: now}
		l.buckets[key] = b
	}

	// Refill tokens based on elapsed time
	elapsed := now.Sub(b.lastTime).Seconds()
	b.tokens = min(l.burst, b.tokens+elapsed*l.rate)
	b.lastTime = now

	if b.tokens < cost {
		return false
	}
	b.tokens -= cost
	return true
}

func (l *Limiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		l.mu.Lock()
		cutoff := time.Now().Add(-10 * time.Minute)
		for key, b := range l.buckets {
			if b.lastTime.Before(cutoff) {
				delete(l.buckets, key)
			}
		}
		l.mu.Unlock()
	}
}

func min(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
