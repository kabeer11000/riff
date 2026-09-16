<?php
require __DIR__ . '/_innertube.php';

$q = $_GET['q'] ?? '';
$limit = max(1, min(50, (int)($_GET['limit'] ?? 20)));
if ($q === '') {
    json_fail(400, 'missing q');
}

$data = innertube_post('search', ['query' => $q]);

$out = [];
$sections = $data['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'] ?? [];
foreach ($sections as $section) {
    $items = $section['itemSectionRenderer']['contents'] ?? [];
    foreach ($items as $item) {
        $v = $item['videoRenderer'] ?? null;
        if ($v === null) continue;

        $id = $v['videoId'] ?? '';
        if ($id === '') continue;

        $uploader = $v['ownerText']['runs'][0]['text'] ?? '';
        $channelId = $v['ownerText']['runs'][0]['navigationEndpoint']['browseEndpoint']['browseId'] ?? '';

        $out[] = [
            'id' => $id,
            'title' => $v['title']['runs'][0]['text'] ?? '',
            'uploader' => $uploader,
            'channel' => $uploader,
            'channelId' => $channelId,
            'duration' => parse_duration_text($v['lengthText']['simpleText'] ?? null),
            'thumbnail' => best_thumbnail($v['thumbnail']['thumbnails'] ?? []),
        ];

        if (count($out) >= $limit) break 2;
    }
}

cors_json($out);
