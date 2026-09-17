<?php
// Shared InnerTube (YouTube's internal web API) client. INNERTUBE_KEY and
// CLIENT_VERSION are the same constants baked into every youtube.com page
// load — public, not a credential of ours.
const INNERTUBE_KEY = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
const CLIENT_VERSION = '2.20240101.01.00';
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function json_fail(int $status, string $message): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode(['error' => $message]);
    exit;
}

function cors_json($data): void {
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

// load_session reads phprelay/cookies.php (gitignored, holds a real logged-in
// YouTube session exported from cookies.txt) if present. Returns null when
// absent so innertube_post falls back to anonymous requests rather than
// failing — the cookie file is an optional hardening, not a hard dependency.
function load_session(): ?array {
    static $loaded = false;
    static $session = null;
    if ($loaded) return $session;
    $loaded = true;
    $path = __DIR__ . '/cookies.php';
    if (is_file($path)) {
        $session = require $path;
    }
    return $session;
}

// sapisidhash implements YouTube's Authorization scheme for authenticated
// InnerTube calls: SAPISIDHASH {ts}_{sha1("{ts} {sapisid} {origin}")}.
function sapisidhash(string $sapisid, string $origin): string {
    $ts = time();
    $hash = sha1("$ts $sapisid $origin");
    return "SAPISIDHASH {$ts}_{$hash}";
}

// innertube_post calls https://www.youtube.com/youtubei/v1/{endpoint} with
// the WEB client context and returns the decoded response body. Uses the
// logged-in session from cookies.php when available — authenticated
// requests are far less likely to be rate-limited/blocked than anonymous
// ones.
function innertube_post(string $endpoint, array $body): array {
    $body['context'] = [
        'client' => [
            'clientName' => 'WEB',
            'clientVersion' => CLIENT_VERSION,
            'hl' => 'en',
            'gl' => 'US',
        ],
    ];

    $origin = 'https://www.youtube.com';
    $headers = [
        'Content-Type: application/json',
        'User-Agent: ' . USER_AGENT,
        'Origin: ' . $origin,
        'X-Origin: ' . $origin,
    ];
    $session = load_session();
    if ($session !== null && !empty($session['cookie'])) {
        $headers[] = 'Cookie: ' . $session['cookie'];
        if (!empty($session['sapisid'])) {
            $headers[] = 'Authorization: ' . sapisidhash($session['sapisid'], $origin);
        }
    }

    $ch = curl_init('https://www.youtube.com/youtubei/v1/' . $endpoint . '?key=' . INNERTUBE_KEY);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($body),
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_CONNECTTIMEOUT => 10,
    ]);
    $raw = curl_exec($ch);
    $err = curl_error($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($raw === false) {
        json_fail(502, "innertube request failed: $err");
    }
    if ($code !== 200) {
        json_fail(502, "innertube returned http $code");
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        json_fail(502, 'innertube returned invalid json');
    }
    return $data;
}

// parse_duration_text converts "3:45" / "1:02:03" into seconds. Returns 0 for
// live streams ("LIVE") or anything unparseable.
function parse_duration_text(?string $text): float {
    if ($text === null || $text === '') return 0.0;
    $parts = explode(':', $text);
    foreach ($parts as $p) {
        if (!ctype_digit($p)) return 0.0;
    }
    $seconds = 0;
    foreach ($parts as $p) {
        $seconds = $seconds * 60 + (int)$p;
    }
    return (float)$seconds;
}

function starts_with(string $haystack, string $needle): bool {
    return substr($haystack, 0, strlen($needle)) === $needle;
}

function best_thumbnail(array $thumbnails): string {
    if (empty($thumbnails)) return '';
    $last = end($thumbnails);
    return $last['url'] ?? '';
}
