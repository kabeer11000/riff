<?php
// Remote deploy endpoint for this folder. Lets the Go backend push updated
// search.php/video.php/playlist.php/channel.php/_innertube.php without
// manual FTP, using the same AES-challenge bypass it uses to read them.
//
// Auth: X-Updater-Token header must match updater-secret.php (sibling file,
// gitignored, uploaded manually alongside this one). Writes are restricted to
// plain *.php filenames in this same directory — no path traversal, and this
// script refuses to overwrite itself or the secret file.

header('Content-Type: application/json');

$secretFile = __DIR__ . '/updater-secret.php';
if (!is_file($secretFile)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'updater secret not configured']);
    exit;
}
$secret = trim((string) require $secretFile);

$token = $_SERVER['HTTP_X_UPDATER_TOKEN'] ?? '';
if ($secret === '' || !hash_equals($secret, $token)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'forbidden']);
    exit;
}

$name = $_POST['name'] ?? '';
$content = $_POST['content'] ?? '';

if ($name === '' || $content === '') {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'missing name/content']);
    exit;
}

// Whitelist: plain filename, .php extension, no directory separators, no "..".
if (!preg_match('/^[A-Za-z0-9_.-]+\.php$/', $name) || strpos($name, '..') !== false) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'invalid filename']);
    exit;
}
if ($name === basename(__FILE__) || $name === basename($secretFile)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'refusing to overwrite self/secret']);
    exit;
}

$path = __DIR__ . '/' . $name;
$bytes = file_put_contents($path, $content);
if ($bytes === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'write failed']);
    exit;
}

echo json_encode(['ok' => true, 'file' => $name, 'bytes' => $bytes]);
