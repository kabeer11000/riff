// Package provider abstracts content sources. The only implementation today is
// YouTube; Spotify/MusicBrainz land behind this interface later.
package provider

import "context"

// Result is one hit from a provider search or single-resolve. It is
// provider-agnostic: ExternalID is opaque to riff and only meaningful inside
// its provider. URL, ISRC, MBID, Metadata are optional.
type Result struct {
	ExternalID string
	Title      string
	Artists    []string
	Album      string
	Duration   float64
	Thumbnail  string
	ISRC       string
	MBID       string
	URL        string
	Metadata   map[string]any
}

// Provider fetches content from a single external source.
type Provider interface {
	Name() string
	Search(ctx context.Context, query string, limit int) ([]Result, error)
	Resolve(ctx context.Context, externalID string) (Result, error)
}
