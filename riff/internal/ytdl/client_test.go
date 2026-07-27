package ytdl

import "testing"

func TestParseExpire(t *testing.T) {
	cases := []struct {
		name, url string
		want      int64
	}{
		{"googlevideo with expire", "https://rr1---sn-xyz.googlevideo.com/videoplayback?expire=1743120000&id=abc&itag=140", 1743120000},
		{"expire in middle", "https://x?itag=140&expire=1234567890&sig=foo", 1234567890},
		{"no expire param", "https://x?itag=140&sig=foo", 0},
		{"empty", "", 0},
		{"expire non-numeric", "https://x?expire=abc", 0},
		{"expire empty value", "https://x?expire=&itag=140", 0},
		{"expire trailing after equals with no digits", "https://x?itag=140&expire=", 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := parseExpire(tc.url); got != tc.want {
				t.Fatalf("parseExpire(%q)=%d want %d", tc.url, got, tc.want)
			}
		})
	}
}