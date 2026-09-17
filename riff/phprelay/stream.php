<?php
// Resolves a directly-playable googlevideo URL for a video id, using the
// ANDROID InnerTube client (see _innertube.php) which returns plain `url`
// fields instead of the WEB client's signature-ciphered ones. We have no way
// to decipher those in PHP, so this only ever returns formats that already
// come back playable — nothing here attempts to descramble a cipher.
require __DIR__ . '/_innertube.php';

$id = $_GET['id'] ?? '';
$kind = $_GET['kind'] ?? 'audio';
if ($id === '') {
    json_fail(400, 'missing id');
}
if ($kind !== 'audio' && $kind !== 'muxed') {
    json_fail(400, 'kind must be audio or muxed');
}

$data = innertube_post('player', [
    'videoId' => $id,
    'params' => '',
    'playbackContext' => [
        'contentPlaybackContext' => ['html5Preference' => 'HTML5_PREF_WANTS'],
    ],
    'contentCheckOk' => true,
    'racyCheckOk' => true,
], 'ANDROID');

$status = $data['playabilityStatus']['status'] ?? 'ERROR';
if ($status !== 'OK') {
    json_fail(404, 'not playable: ' . $status);
}

$streaming = $data['streamingData'] ?? [];
$candidates = $kind === 'muxed' ? ($streaming['formats'] ?? []) : ($streaming['adaptiveFormats'] ?? []);

$best = null;
foreach ($candidates as $f) {
    // Skip anything without a plain url — signatureCipher/cipher formats need
    // YouTube's player JS to decode, which we can't do in PHP.
    if (empty($f['url'])) continue;
    if ($kind === 'audio') {
        if (!starts_with($f['mimeType'] ?? '', 'audio/')) continue;
        if ($best === null || ($f['bitrate'] ?? 0) > ($best['bitrate'] ?? 0)) $best = $f;
    } else {
        if (!starts_with($f['mimeType'] ?? '', 'video/')) continue;
        if ($best === null || ($f['height'] ?? 0) > ($best['height'] ?? 0)) $best = $f;
    }
}

if ($best === null) {
    json_fail(502, "no directly-playable $kind format for $id");
}

$expiresAt = 0;
if (preg_match('/[?&]expire=(\d+)/', $best['url'], $m)) {
    $expiresAt = (int)$m[1];
}

cors_json([
    'url' => $best['url'],
    'mimeType' => $best['mimeType'] ?? '',
    'expiresAt' => $expiresAt,
]);
