<?php
require __DIR__ . '/_innertube.php';

$id = $_GET['id'] ?? '';
if ($id === '') {
    json_fail(400, 'missing id');
}

$browseId = starts_with($id, 'VL') ? $id : 'VL' . $id;
$data = innertube_post('browse', ['browseId' => $browseId]);

$title = $data['header']['playlistHeaderRenderer']['title']['simpleText']
    ?? $data['metadata']['playlistMetadataRenderer']['title']
    ?? $id;

$entries = [];
$tabs = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'] ?? [];
foreach ($tabs as $tab) {
    $sections = $tab['tabRenderer']['content']['sectionListRenderer']['contents'] ?? [];
    foreach ($sections as $section) {
        $items = $section['itemSectionRenderer']['contents'][0]['playlistVideoListRenderer']['contents'] ?? [];
        foreach ($items as $item) {
            $v = $item['playlistVideoRenderer'] ?? null;
            if ($v === null) continue;

            $vid = $v['videoId'] ?? '';
            if ($vid === '') continue;

            $entries[] = [
                'id' => $vid,
                'title' => $v['title']['runs'][0]['text'] ?? '',
                'uploader' => $v['shortBylineText']['runs'][0]['text'] ?? '',
                'duration' => (float)($v['lengthSeconds'] ?? 0),
                'thumbnail' => best_thumbnail($v['thumbnail']['thumbnails'] ?? []),
            ];
        }
    }
}

// ponytail: first page only, no continuation-token pagination. Add a
// continuation loop (browse endpoint's continuationCommand) if playlists
// routinely run past ~100 entries.
cors_json(['title' => $title, 'entries' => $entries]);
