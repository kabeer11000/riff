// Command phprelaydeploy pushes riff/phprelay/*.php to the InfinityFree PHP
// relay via updater.php, then runs a smoke test against the deployed
// endpoints. updater.php and updater-secret.php themselves are never
// deployed by this tool — they're the manually-uploaded bootstrap; this tool
// only pushes the files updater.php is willing to overwrite.
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"riff/m/internal/phpscraper"
)

func main() {
	base := flag.String("base", "", "base URL of the phprelay folder, e.g. https://xxx.rf.gd/phprelay")
	dir := flag.String("dir", "phprelay", "local directory containing the PHP files")
	secretFile := flag.String("secret-file", "", "local updater-secret.php path (default: <dir>/updater-secret.php)")
	runTest := flag.Bool("test", true, "run a smoke test against search.php/video.php after deploying")
	skipDeploy := flag.Bool("skip-deploy", false, "skip the deploy step and only run the smoke test against already-deployed files")
	testQuery := flag.String("test-query", "lofi hip hop", "search query used for the smoke test")
	testVideoID := flag.String("test-video-id", "dQw4w9WgXcQ", "video id used for the smoke test")
	flag.Parse()

	if *base == "" {
		fmt.Fprintln(os.Stderr, "error: -base is required")
		os.Exit(1)
	}
	if *secretFile == "" {
		*secretFile = filepath.Join(*dir, "updater-secret.php")
	}

	client := phpscraper.New(strings.TrimRight(*base, "/"))
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	if !*skipDeploy {
		token, err := readSecret(*secretFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: reading secret: %v\n", err)
			os.Exit(1)
		}

		files, err := filepath.Glob(filepath.Join(*dir, "*.php"))
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: listing %s: %v\n", *dir, err)
			os.Exit(1)
		}

		deployed := 0
		for _, f := range files {
			name := filepath.Base(f)
			if name == "updater.php" || name == "updater-secret.php" {
				continue
			}
			content, err := os.ReadFile(f)
			if err != nil {
				fmt.Fprintf(os.Stderr, "error: reading %s: %v\n", f, err)
				os.Exit(1)
			}
			if err := client.Deploy(ctx, token, name, string(content)); err != nil {
				fmt.Fprintf(os.Stderr, "FAIL deploy %s: %v\n", name, err)
				os.Exit(1)
			}
			fmt.Printf("OK   deploy %s (%d bytes)\n", name, len(content))
			deployed++
		}
		fmt.Printf("deployed %d file(s)\n", deployed)
	}

	if !*runTest {
		return
	}
	runSmokeTest(ctx, client, *testQuery, *testVideoID)
}

func readSecret(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	re := regexp.MustCompile(`return\s+['"]([^'"]+)['"]\s*;`)
	m := re.FindStringSubmatch(string(data))
	if m == nil {
		return "", fmt.Errorf("no `return '...';` found in %s", path)
	}
	return m[1], nil
}

func runSmokeTest(ctx context.Context, client *phpscraper.Client, query, videoID string) {
	fmt.Println("--- smoke test ---")
	ok := true

	if hits, err := client.Search(ctx, query, 5); err != nil {
		fmt.Printf("FAIL search(%q): %v\n", query, err)
		ok = false
	} else if len(hits) == 0 {
		fmt.Printf("FAIL search(%q): 0 results (innertube JSON path likely drifted)\n", query)
		ok = false
	} else {
		fmt.Printf("OK   search(%q): %d results, first = %q (%s)\n", query, len(hits), hits[0].Title, hits[0].ID)
	}

	if info, err := client.ResolveInfo(ctx, videoID); err != nil {
		fmt.Printf("FAIL resolve(%s): %v\n", videoID, err)
		ok = false
	} else if info.Title == "" {
		fmt.Printf("FAIL resolve(%s): empty title (innertube JSON path likely drifted)\n", videoID)
		ok = false
	} else {
		fmt.Printf("OK   resolve(%s): %q by %q, %.0fs\n", videoID, info.Title, info.Uploader, info.Duration)
	}

	if rs, err := client.ResolveStream(ctx, videoID, "audio"); err != nil {
		fmt.Printf("FAIL stream(%s): %v\n", videoID, err)
		ok = false
	} else {
		fmt.Printf("OK   stream(%s): %s, expires %s\n", videoID, rs.ContentType, rs.ExpiresAt)
		if code, err := fetchStatus(ctx, rs.URL); err != nil {
			fmt.Printf("FAIL fetch resolved url: %v\n", err)
			ok = false
		} else if code != 200 && code != 206 {
			fmt.Printf("FAIL fetch resolved url: http %d (this is exactly the Render 403 problem)\n", code)
			ok = false
		} else {
			fmt.Printf("OK   fetch resolved url: http %d\n", code)
		}
	}

	if !ok {
		os.Exit(1)
	}
}

// fetchStatus sends a ranged GET against a resolved stream URL from this
// machine, mirroring what the Go backend's stream.Proxy does. A non-2xx here
// (403 in particular) means the URL wasn't actually usable despite resolving
// without a cipher.
func fetchStatus(ctx context.Context, url string) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Range", "bytes=0-1023")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}
