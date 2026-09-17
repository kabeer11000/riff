package index

import (
	"context"
	"fmt"
	"testing"

	"riff/m/internal/domain"
	"riff/m/internal/provider"
	"riff/m/internal/store"
)

// fakeRepo implements only the methods Index touches; embedding the nil
// interface satisfies the rest of store.Repository without stubbing it all.
type fakeRepo struct {
	store.Repository
	failExternalID string
}

func (f *fakeRepo) LookupBySource(ctx context.Context, provider, externalID string) (string, bool, error) {
	return "", false, nil
}

func (f *fakeRepo) LookupByCanonical(ctx context.Context, isrc, mbid string) (string, bool, error) {
	return "", false, nil
}

func (f *fakeRepo) CreateItem(ctx context.Context, item domain.Item) (string, error) {
	return "id-" + item.Title, nil
}

func (f *fakeRepo) AddSource(ctx context.Context, itemID string, src domain.Source) error {
	if src.ExternalID == f.failExternalID {
		return fmt.Errorf("boom: %s", src.ExternalID)
	}
	return nil
}

func (f *fakeRepo) GetItem(ctx context.Context, id string) (domain.Item, error) {
	return domain.Item{ID: id}, nil
}

func TestIndexPreservesOrderUnderConcurrency(t *testing.T) {
	results := make([]provider.Result, 0, 20)
	for i := 0; i < 20; i++ {
		results = append(results, provider.Result{
			ExternalID: fmt.Sprintf("ext-%d", i),
			Title:      fmt.Sprintf("title-%d", i),
		})
	}
	ix := New(&fakeRepo{})
	items, err := ix.Index(context.Background(), "youtube", results)
	if err != nil {
		t.Fatalf("Index() error = %v", err)
	}
	if len(items) != len(results) {
		t.Fatalf("len(items) = %d, want %d", len(items), len(results))
	}
	for i, r := range results {
		want := "id-" + r.Title
		if items[i].ID != want {
			t.Errorf("items[%d].ID = %q, want %q (order not preserved)", i, items[i].ID, want)
		}
	}
}

func TestIndexPropagatesError(t *testing.T) {
	results := []provider.Result{
		{ExternalID: "ext-0", Title: "ok"},
		{ExternalID: "ext-1", Title: "bad"},
	}
	ix := New(&fakeRepo{failExternalID: "ext-1"})
	_, err := ix.Index(context.Background(), "youtube", results)
	if err == nil {
		t.Fatal("Index() error = nil, want error from failed AddSource")
	}
}
