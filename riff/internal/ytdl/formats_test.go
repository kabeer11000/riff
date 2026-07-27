package ytdl

import "testing"

func TestClassify(t *testing.T) {
	cases := []struct {
		name, acodec, vcodec, want string
	}{
		{"audio only", "mp4a.40.2", "none", "audio"},
		{"opus audio", "opus", "none", "audio"},
		{"muxed mp4", "mp4a.40.2", "avc1.42001E", "muxed"},
		{"video only", "none", "avc1.640028", ""},
		{"empty pair", "", "", ""},
		{"video only no audio", "", "avc1", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := classify(tc.acodec, tc.vcodec); got != tc.want {
				t.Fatalf("classify(%q,%q)=%q want %q", tc.acodec, tc.vcodec, got, tc.want)
			}
		})
	}
}

func TestDirectable(t *testing.T) {
	cases := []struct {
		name, protocol string
		want           bool
	}{
		{"https", "https", true},
		{"http", "http", true},
		{"blank (default)", "", true},
		{"m3u8", "m3u8_native", false},
		{"dash", "http_dash_segments", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := streamFormat{URL: "https://x", Protocol: tc.protocol}
			if got := directable(f); got != tc.want {
				t.Fatalf("directable(protocol=%q)=%v want %v", tc.protocol, got, tc.want)
			}
		})
	}
}

func TestPickBest(t *testing.T) {
	all := []streamFormat{
		{FormatID: "low-audio", Kind: "audio", ABR: 48, URL: "https://x", Protocol: "https"},
		{FormatID: "high-audio", Kind: "audio", ABR: 129, URL: "https://x", Protocol: "https"},
		{FormatID: "video-only", Kind: "", ABR: 0, Height: 720, URL: "https://x", Protocol: "https"},
		{FormatID: "muxed-360", Kind: "muxed", ABR: 100, Height: 360, URL: "https://x", Protocol: "https"},
		{FormatID: "muxed-720", Kind: "muxed", ABR: 200, Height: 720, URL: "https://x", Protocol: "https"},
		{FormatID: "muxed-dash", Kind: "muxed", ABR: 500, Height: 1080, URL: "https://x", Protocol: "http_dash_segments"},
		{FormatID: "no-url", Kind: "audio", ABR: 999, URL: "", Protocol: "https"},
	}

	t.Run("audio picks highest ABR", func(t *testing.T) {
		best := pickBest(all, "audio")
		if best == nil || best.FormatID != "high-audio" {
			t.Fatalf("got %v want high-audio", best)
		}
	})

	t.Run("muxed picks highest height skipping non-direct", func(t *testing.T) {
		best := pickBest(all, "muxed")
		if best == nil || best.FormatID != "muxed-720" {
			t.Fatalf("got %v want muxed-720", best)
		}
	})

	t.Run("no match", func(t *testing.T) {
		if best := pickBest(all, "video"); best != nil {
			t.Fatalf("got %v want nil for empty-kind filter", best)
		}
	})

	t.Run("only dash muxed → none", func(t *testing.T) {
		dash := []streamFormat{{FormatID: "dash", Kind: "muxed", Height: 1080, URL: "https://x", Protocol: "http_dash_segments"}}
		if best := pickBest(dash, "muxed"); best != nil {
			t.Fatalf("got %v want nil for dash-only", best)
		}
	})
}

func TestContentType(t *testing.T) {
	cases := []struct {
		kind, ext, want string
	}{
		{"audio", "m4a", "audio/mp4"},
		{"audio", "webm", "audio/webm"},
		{"audio", "opus", "audio/webm"},
		{"audio", "mp3", "audio/mpeg"},
		{"audio", "ogg", "audio/mpeg"},
		{"muxed", "webm", "video/webm"},
		{"muxed", "mp4", "video/mp4"},
		{"muxed", "m4a", "video/mp4"},
	}
	for _, tc := range cases {
		t.Run(tc.kind+"/"+tc.ext, func(t *testing.T) {
			f := &streamFormat{Kind: tc.kind, Ext: tc.ext}
			if got := contentType(f); got != tc.want {
				t.Fatalf("contentType(kind=%q,ext=%q)=%q want %q", tc.kind, tc.ext, got, tc.want)
			}
		})
	}
}