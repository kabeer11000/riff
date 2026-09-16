<?php
require __DIR__ . '/_innertube.php';

$id = $_GET['id'] ?? '';
if ($id === '') {
    json_fail(400, 'missing id');
}

// params = the "Videos" tab selector InnerTube's own web client sends when
// you click a channel's Videos tab. If YouTube reshuffles this blob, the
// browse call falls back to whatever the default (Home) tab returns.
$data = innertube_post('browse', ['browseId' => $id, 'params' => 'EgZ2aWRlb3PyBgQKAjoA']);

$title = $data['metadata']['channelMetadataRenderer']['title'] ?? $id;

$entries = [];
$tabs = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'] ?? [];
foreach ($tabs as $tab) {
    $items = $tab['tabRenderer']['content']['richGridRenderer']['contents'] ?? [];
    foreach ($items as $item) {
        $v = $item['richItemRenderer']['content']['videoRenderer'] ?? null;
        if ($v === null) continue;

        $vid = $v['videoId'] ?? '';
        if ($vid === '') continue;

        $entries[] = [
            'id' => $vid,
            'title' => $v['title']['runs'][0]['text'] ?? ($v['title']['simpleText'] ?? ''),
            'uploader' => $title,
            'duration' => parse_duration_text($v['lengthText']['simpleText'] ?? null),
            'thumbnail' => best_thumbnail($v['thumbnail']['thumbnails'] ?? []),
        ];
    }
}

// ponytail: first page only, no continuation-token pagination. Add a
// continuation loop if channels routinely need more than the first grid.
cors_json(['title' => $title, 'entries' => $entries]);
