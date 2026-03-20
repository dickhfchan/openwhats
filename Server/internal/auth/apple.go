package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const appleJWKSURL = "https://appleid.apple.com/auth/keys"
const appleIssuer = "https://appleid.apple.com"

type jwk struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type jwksResponse struct {
	Keys []jwk `json:"keys"`
}

// jwksCache caches Apple's public keys with a 1-hour TTL.
var jwksCache struct {
	sync.RWMutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

func getApplePublicKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	jwksCache.RLock()
	if time.Since(jwksCache.fetchedAt) < time.Hour {
		key := jwksCache.keys[kid]
		jwksCache.RUnlock()
		if key != nil {
			return key, nil
		}
	} else {
		jwksCache.RUnlock()
	}

	// Refresh cache
	keys, err := fetchAppleJWKS(ctx)
	if err != nil {
		return nil, err
	}

	jwksCache.Lock()
	jwksCache.keys = keys
	jwksCache.fetchedAt = time.Now()
	jwksCache.Unlock()

	key, ok := keys[kid]
	if !ok {
		return nil, fmt.Errorf("apple: key id %q not found in JWKS", kid)
	}
	return key, nil
}

func fetchAppleJWKS(ctx context.Context) (map[string]*rsa.PublicKey, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, appleJWKSURL, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch apple JWKS: %w", err)
	}
	defer resp.Body.Close()

	var jwks jwksResponse
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("decode apple JWKS: %w", err)
	}

	keys := make(map[string]*rsa.PublicKey, len(jwks.Keys))
	for _, k := range jwks.Keys {
		pub, err := jwkToRSA(k)
		if err != nil {
			continue
		}
		keys[k.Kid] = pub
	}
	return keys, nil
}

func jwkToRSA(k jwk) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(k.N)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
	if err != nil {
		return nil, err
	}
	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(nBytes),
		E: int(new(big.Int).SetBytes(eBytes).Int64()),
	}, nil
}

// VerifyAppleToken validates an Apple identity token and returns the Apple user sub.
// bundleIDs should contain all accepted audience values (iOS + macOS bundle IDs).
func VerifyAppleToken(ctx context.Context, identityToken string, bundleIDs []string) (string, error) {
	// Parse without verification to extract kid from header
	unverified, _, err := jwt.NewParser().ParseUnverified(identityToken, jwt.MapClaims{})
	if err != nil {
		return "", fmt.Errorf("apple: parse token: %w", err)
	}

	kid, ok := unverified.Header["kid"].(string)
	if !ok || kid == "" {
		return "", fmt.Errorf("apple: missing kid in token header")
	}

	pubKey, err := getApplePublicKey(ctx, kid)
	if err != nil {
		return "", err
	}

	var claims jwt.MapClaims
	_, err = jwt.NewParser(
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithIssuedAt(),
		jwt.WithExpirationRequired(),
	).ParseWithClaims(identityToken, &claims, func(t *jwt.Token) (any, error) {
		return pubKey, nil
	})
	if err != nil {
		return "", fmt.Errorf("apple: token invalid: %w", err)
	}

	// Validate issuer
	iss, _ := claims["iss"].(string)
	if iss != appleIssuer {
		return "", fmt.Errorf("apple: invalid issuer %q", iss)
	}

	// Validate audience (one of the accepted bundle IDs)
	aud := audienceFromClaims(claims)
	if !containsAny(aud, bundleIDs) {
		return "", fmt.Errorf("apple: invalid audience %v", aud)
	}

	sub, _ := claims["sub"].(string)
	if sub == "" {
		return "", fmt.Errorf("apple: missing sub claim")
	}
	return sub, nil
}

func audienceFromClaims(claims jwt.MapClaims) []string {
	switch v := claims["aud"].(type) {
	case string:
		return []string{v}
	case []any:
		var out []string
		for _, a := range v {
			if s, ok := a.(string); ok {
				out = append(out, s)
			}
		}
		return out
	}
	return nil
}

func containsAny(haystack, needles []string) bool {
	for _, n := range needles {
		for _, h := range haystack {
			if strings.EqualFold(h, n) {
				return true
			}
		}
	}
	return false
}
