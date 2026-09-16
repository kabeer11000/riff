// Package phpscraper implements ytdl.Source against a set of PHP scripts
// hosted on free PHP-only shared hosting (InfinityFree). The host fronts every
// request with a JS "anti-bot" challenge: an HTML page that AES-decrypts a
// payload in-browser and sets the result as a cookie before redirecting.
// solveChallenge reproduces that decryption in Go so a plain HTTP client can
// pass it without executing JS.
package phpscraper

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/hex"
	"fmt"
	"regexp"
)

// challengeRe pulls the three toNumbers("...") hex blobs out of the challenge
// page, in (key, iv, ciphertext) order — the page calls
// slowAES.decrypt(cipherText=c, mode=2, key=a, iv=b), so the 1st/2nd vars are
// key/iv despite reading like (a=iv-shaped, b=key-shaped) at a glance.
var challengeRe = regexp.MustCompile(`(?s)toNumbers\("([0-9a-f]+)"\).*?toNumbers\("([0-9a-f]+)"\).*?toNumbers\("([0-9a-f]+)"\)`)

const challengeCookieName = "__test"

// isChallenge reports whether body is the anti-bot challenge page rather than
// real content.
func isChallenge(body string) bool {
	return challengeRe.MatchString(body)
}

// solveChallenge extracts (key, iv, ciphertext) from the challenge page body
// and returns the cookie value (hex-encoded AES-128-CBC plaintext) the real
// browser would have set.
func solveChallenge(body string) (string, error) {
	m := challengeRe.FindStringSubmatch(body)
	if m == nil {
		return "", fmt.Errorf("phpscraper: no challenge payload found")
	}
	key, err := hex.DecodeString(m[1])
	if err != nil {
		return "", fmt.Errorf("phpscraper: bad challenge key: %w", err)
	}
	iv, err := hex.DecodeString(m[2])
	if err != nil {
		return "", fmt.Errorf("phpscraper: bad challenge iv: %w", err)
	}
	ct, err := hex.DecodeString(m[3])
	if err != nil {
		return "", fmt.Errorf("phpscraper: bad challenge ciphertext: %w", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("phpscraper: aes.NewCipher: %w", err)
	}
	if len(ct) != block.BlockSize() || len(iv) != block.BlockSize() {
		return "", fmt.Errorf("phpscraper: unexpected challenge block size")
	}
	pt := make([]byte, len(ct))
	cipher.NewCBCDecrypter(block, iv).CryptBlocks(pt, ct)
	return hex.EncodeToString(pt), nil
}
