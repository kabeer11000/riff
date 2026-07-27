package ytdl

import "encoding/json"

// streamFormat is a format parsed from yt-dlp's raw JSON, including the direct
// media URL that goutubedl.Format omits.
type streamFormat struct {
	FormatID string
	URL      string
	Ext      string
	ACodec   string
	VCodec   string
	ABR      float64
	Height   float64
	Filesize float64
	Protocol string
	Kind     string // "audio" | "muxed" | "" (video-only / not directly usable)
}

// parseFormats extracts formats with their direct URLs from yt-dlp raw JSON.
func parseFormats(rawJSON []byte) ([]streamFormat, error) {
	var doc struct {
		Formats []struct {
			FormatID string  `json:"format_id"`
			URL      string  `json:"url"`
			Ext      string  `json:"ext"`
			ACodec   string  `json:"acodec"`
			VCodec   string  `json:"vcodec"`
			ABR      float64 `json:"abr"`
			Height   float64 `json:"height"`
			Filesize float64 `json:"filesize"`
			Protocol string  `json:"protocol"`
		} `json:"formats"`
	}
	if err := json.Unmarshal(rawJSON, &doc); err != nil {
		return nil, err
	}
	out := make([]streamFormat, 0, len(doc.Formats))
	for _, f := range doc.Formats {
		sf := streamFormat{
			FormatID: f.FormatID,
			URL:      f.URL,
			Ext:      f.Ext,
			ACodec:   f.ACodec,
			VCodec:   f.VCodec,
			ABR:      f.ABR,
			Height:   f.Height,
			Filesize: f.Filesize,
			Protocol: f.Protocol,
			Kind:     classify(f.ACodec, f.VCodec),
		}
		out = append(out, sf)
	}
	return out, nil
}

func classify(acodec, vcodec string) string {
	hasA := acodec != "" && acodec != "none"
	hasV := vcodec != "" && vcodec != "none"
	switch {
	case hasA && hasV:
		return "muxed"
	case hasA && !hasV:
		return "audio"
	default:
		return "" // video-only or unknown — not offered as a playable kind
	}
}

// directable reports whether a format is a single, directly-fetchable file we
// can proxy with Range requests (i.e. not an HLS/DASH manifest).
func directable(f streamFormat) bool {
	if f.URL == "" {
		return false
	}
	switch f.Protocol {
	case "https", "http", "":
		return true
	default:
		return false // m3u8, m3u8_native, http_dash_segments, etc.
	}
}

// pickBest chooses the best directly-proxyable format of the requested kind.
// audio: highest ABR. muxed: highest resolution, then bitrate.
func pickBest(formats []streamFormat, kind string) *streamFormat {
	var best *streamFormat
	for i := range formats {
		f := &formats[i]
		if f.Kind != kind || !directable(*f) {
			continue
		}
		if best == nil {
			best = f
			continue
		}
		switch kind {
		case "audio":
			if f.ABR > best.ABR {
				best = f
			}
		case "muxed":
			if f.Height > best.Height || (f.Height == best.Height && f.ABR > best.ABR) {
				best = f
			}
		}
	}
	return best
}

func contentType(f *streamFormat) string {
	if f.Kind == "audio" {
		switch f.Ext {
		case "m4a", "mp4":
			return "audio/mp4"
		case "webm", "opus":
			return "audio/webm"
		case "mp3":
			return "audio/mpeg"
		}
		return "audio/mpeg"
	}
	// muxed
	switch f.Ext {
	case "webm":
		return "video/webm"
	default:
		return "video/mp4"
	}
}
