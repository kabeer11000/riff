package provider

import "regexp"

// urlPatterns maps provider URL shapes to a capture group containing the
// external id. Add a row when a new provider lands.
var urlPatterns = []struct {
	Provider string
	Pattern  *regexp.Regexp
	Group    int
}{
	{"youtube", regexp.MustCompile(`youtube\.com/watch\?v=([A-Za-z0-9_-]{11})`), 1},
	{"youtube", regexp.MustCompile(`youtu\.be/([A-Za-z0-9_-]{11})`), 1},
}

// DetectURL returns (provider, externalID) for a recognised URL.
// ok=false when no pattern matches; callers should return 400.
func DetectURL(raw string) (string, string, bool) {
	for _, p := range urlPatterns {
		if m := p.Pattern.FindStringSubmatch(raw); m != nil {
			return p.Provider, m[p.Group], true
		}
	}
	return "", "", false
}
