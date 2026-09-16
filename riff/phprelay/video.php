<?php
require __DIR__ . '/_innertube.php';

$id = $_GET['id'] ?? '';
if ($id === '') {
    json_fail(400, 'missing id');
}

$data = innertube_post('player', ['videoId' => $id]);

$details = $data['videoDetails'] ?? null;
if ($details === null) {
    json_fail(404, 'video not found');
}

$micro = $data['microformat']['playerMicroformatRenderer'] ?? [];

cors_json([
    'id' => $details['videoId'] ?? $id,
    'title' => $details['title'] ?? '',
    'uploader' => $details['author'] ?? '',
    'channel' => $details['author'] ?? '',
    'channelId' => $details['channelId'] ?? '',
    'duration' => (float)($details['lengthSeconds'] ?? 0),
    'thumbnail' => best_thumbnail($details['thumbnail']['thumbnails'] ?? []),
    'description' => $details['shortDescription'] ?? '',
    'viewCount' => (int)($details['viewCount'] ?? 0),
    'uploadDate' => $micro['uploadDate'] ?? '',
]);
