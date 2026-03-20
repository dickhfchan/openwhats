// testtoken generates a dev JWT for manual API testing.
// Usage: go run ./cmd/testtoken/ <user_id>
package main

import (
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func main() {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "openwhats-dev-secret-change-in-prod-32chars"
	}
	userID := "00000000-0000-0000-0000-000000000001"
	if len(os.Args) > 1 {
		userID = os.Args[1]
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID,
		"iss":     "openwhats",
		"exp":     time.Now().Add(30 * 24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
	})
	s, err := t.SignedString([]byte(secret))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(s)
}
