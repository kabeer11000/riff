/// Non-web no-op. There's no address bar to sync with.
void syncPlayerUrl({String? videoId, String? listId}) {}

({String? videoId, String? listId}) readUrlState() =>
    (videoId: null, listId: null);
