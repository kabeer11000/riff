package store

import (
	"context"
	"path/filepath"
	"testing"

	"riff/m/internal/domain"
)

func openTestDB(t *testing.T) *SQLite {
	t.Helper()
	db, err := OpenSQLite(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func TestListHistoryGroupsAndOrdersByRecency(t *testing.T) {
	db := openTestDB(t)
	ctx := context.Background()
	if err := db.EnsureUser(ctx, "u1"); err != nil {
		t.Fatal(err)
	}

	// 3 plays of "a" + 1 play of "b", interleaved. The most recent is "a",
	// so the grouped result should be [a(3), b(1)].
	plays := []domain.PlayEvent{
		{VideoID: "a", Title: "Song A", Duration: 200, Position: 10, ContextKind: "search"},
		{VideoID: "b", Title: "Song B", Duration: 700, Position: 0, ContextKind: "playlist", ContextID: "p1", ContextTitle: "My Mix"},
		{VideoID: "a", Title: "Song A", Duration: 200, Position: 30, ContextKind: "search"},
		{VideoID: "a", Title: "Song A", Duration: 200, Position: 60, ContextKind: "library"},
	}
	for _, p := range plays {
		if err := db.RecordPlay(ctx, "u1", p); err != nil {
			t.Fatal(err)
		}
	}

	entries, err := db.ListHistory(ctx, "u1", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2", len(entries))
	}
	if entries[0].VideoID != "a" || entries[0].PlayCount != 3 {
		t.Fatalf("entries[0]=%+v want a with PlayCount=3", entries[0])
	}
	if entries[1].VideoID != "b" || entries[1].PlayCount != 1 {
		t.Fatalf("entries[1]=%+v want b with PlayCount=1", entries[1])
	}
	if entries[0].LastPosition != 60 {
		t.Fatalf("a LastPosition=%v want 60 (max of reported)", entries[0].LastPosition)
	}
	// Context of "a" should come from its most-recent row (library).
	if entries[0].ContextKind != "library" {
		t.Fatalf("a context=%q want library", entries[0].ContextKind)
	}
	// Long-form threshold: a=200s short, b=700s long.
	if entries[0].IsLongForm {
		t.Fatal("a should not be long-form")
	}
	if !entries[1].IsLongForm {
		t.Fatal("b should be long-form")
	}
}

func TestLatestContinueCard(t *testing.T) {
	db := openTestDB(t)
	ctx := context.Background()
	_ = db.EnsureUser(ctx, "u1")

	// No history → ErrNotFound.
	if _, err := db.LatestContinueCard(ctx, "u1"); err != ErrNotFound {
		t.Fatalf("got %v want ErrNotFound", err)
	}

	// Two playlists, one channel. Latest playlist wins.
	_ = db.RecordPlay(ctx, "u1", domain.PlayEvent{VideoID: "x", ContextKind: "playlist", ContextID: "p1", ContextTitle: "First"})
	_ = db.RecordPlay(ctx, "u1", domain.PlayEvent{VideoID: "y", ContextKind: "channel", ContextID: "c1", ContextTitle: "Channel"})
	_ = db.RecordPlay(ctx, "u1", domain.PlayEvent{VideoID: "z", ContextKind: "playlist", ContextID: "p2", ContextTitle: "Second"})

	card, err := db.LatestContinueCard(ctx, "u1")
	if err != nil {
		t.Fatal(err)
	}
	if card.Kind != "playlist" || card.ID != "p2" || card.Title != "Second" {
		t.Fatalf("got %+v want playlist p2 Second", card)
	}
}

func TestDeleteAndClearHistory(t *testing.T) {
	db := openTestDB(t)
	ctx := context.Background()
	_ = db.EnsureUser(ctx, "u1")

	_ = db.RecordPlay(ctx, "u1", domain.PlayEvent{VideoID: "a"})
	_ = db.RecordPlay(ctx, "u1", domain.PlayEvent{VideoID: "b"})

	if err := db.DeleteHistoryTrack(ctx, "u1", "a"); err != nil {
		t.Fatal(err)
	}
	entries, _ := db.ListHistory(ctx, "u1", 10)
	if len(entries) != 1 || entries[0].VideoID != "b" {
		t.Fatalf("after delete: %+v want [b]", entries)
	}

	if err := db.ClearHistory(ctx, "u1"); err != nil {
		t.Fatal(err)
	}
	entries, _ = db.ListHistory(ctx, "u1", 10)
	if len(entries) != 0 {
		t.Fatalf("after clear: %+v want []", entries)
	}
}