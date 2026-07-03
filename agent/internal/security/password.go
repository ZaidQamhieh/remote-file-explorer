package security

import "golang.org/x/crypto/bcrypt"

// HashPassword salts and hashes a user-chosen password with bcrypt — unlike
// the SHA-256 used for high-entropy bearer tokens elsewhere in this package,
// a human password needs a deliberately slow, salted hash to resist offline
// brute force.
func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(hash), err
}

// VerifyPassword reports whether password matches hash (as produced by
// HashPassword).
func VerifyPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
