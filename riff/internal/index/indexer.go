// Package index turns provider results into canonical riff Items. Each Result
// is matched against existing items by (provider, external_id) first, then by
// canonical IDs (ISRC/MBID). New items are minted and linked back to their
// sources.
package index

import (
	"context"

	"riff/m/internal/domain"
	"riff/m/internal/provider"
	"riff/m/internal/store"
)

type Indexer struct {
	Repo store.Repository
}

func New(r store.Repository) *Indexer { return &Indexer{Repo: r} }

// Index maps a list of provider results to canonical items. For each result:
//   1. Look up by (provider, external_id) — reuse existing item if hit.
//   2. Else look up by ISRC/MBID — reuse existing item if hit.
//   3. Else CreateItem + AddSource.
func (ix *Indexer) Index(ctx context.Context, providerName string, results []provider.Result) ([]domain.Item, error) {
	out := make([]domain.Item, 0, len(results))
	for _, r := range results {
		id, found, err := ix.Repo.LookupBySource(ctx, providerName, r.ExternalID)
		if err != nil {
			return nil, err
		}
		if !found {
			id, found, err = ix.Repo.LookupByCanonical(ctx, r.ISRC, r.MBID)
			if err != nil {
				return nil, err
			}
		}
		if !found {
			id, err = ix.Repo.CreateItem(ctx, domain.Item{
				Title:     r.Title,
				Artists:   r.Artists,
				Album:     r.Album,
				Duration:  r.Duration,
				Thumbnail: r.Thumbnail,
			})
			if err != nil {
				return nil, err
			}
		}
		if err := ix.Repo.AddSource(ctx, id, domain.Source{
			Provider:   providerName,
			ExternalID: r.ExternalID,
			URL:        r.URL,
			Metadata:   r.Metadata,
		}); err != nil {
			return nil, err
		}
		EnqueueEmbedding(ctx, id)
		// Re-fetch the canonical item so callers see a fully-populated row
		// (artists JSON round-tripped, sources list populated).
		it, err := ix.Repo.GetItem(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, nil
}
