/// Non-web no-op. There's no address bar to sync with.
void syncPlayerUrl({String? itemId, String? listId}) {}

({String? itemId, String? listId}) readUrlState() =>
    (itemId: null, listId: null);
