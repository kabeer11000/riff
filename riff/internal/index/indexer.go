// Package index turns provider results into canonical riff Items. Each Result
// is matched against existing items by (provider, external_id) first, then by
// canonical IDs (ISRC/MBID). New items are minted and linked back to their
// sources.
package index

import (
	"context"
	"sync"

	"riff/m/internal/domain"
	"riff/m/internal/provider"
	"riff/m/internal/store"
)

// indexConcurrency bounds how many results are indexed at once. Each result
// does ~4 sequential Turso round-trips; running them one result at a time
// made a 20-result search take seconds. Turso is remote HTTP, so this is
// purely I/O wait — safe to fan out.
const indexConcurrency = 8

type Indexer struct {
	Repo store.Repository
}

func New(r store.Repository) *Indexer { return &Indexer{Repo: r} }

// Index maps a list of provider results to canonical items. For each result:
//   1. Look up by (provider, external_id) — reuse existing item if hit.
//   2. Else look up by ISRC/MBID — reuse existing item if hit.
//   3. Else CreateItem + AddSource.
func (ix *Indexer) Index(ctx context.Context, providerName string, results []provider.Result) ([]domain.Item, error) {
	out := make([]domain.Item, len(results))
	ok := make([]bool, len(results))
	var wg sync.WaitGroup
	var mu sync.Mutex
	var firstErr error
	sem := make(chan struct{}, indexConcurrency)

	for i, r := range results {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, r provider.Result) {
			defer wg.Done()
			defer func() { <-sem }()
			it, err := ix.indexOne(ctx, providerName, r)
			if err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				return
			}
			out[i] = it
			ok[i] = true
		}(i, r)
	}
	wg.Wait()
	if firstErr != nil {
		return nil, firstErr
	}

	items := make([]domain.Item, 0, len(out))
	for i, item := range out {
		if ok[i] {
			items = append(items, item)
		}
	}
	return items, nil
}

func (ix *Indexer) indexOne(ctx context.Context, providerName string, r provider.Result) (domain.Item, error) {
	id, found, err := ix.Repo.LookupBySource(ctx, providerName, r.ExternalID)
	if err != nil {
		return domain.Item{}, err
	}
	if !found {
		id, found, err = ix.Repo.LookupByCanonical(ctx, r.ISRC, r.MBID)
		if err != nil {
			return domain.Item{}, err
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
			return domain.Item{}, err
		}
	}
	if err := ix.Repo.AddSource(ctx, id, domain.Source{
		Provider:   providerName,
		ExternalID: r.ExternalID,
		URL:        r.URL,
		Metadata:   r.Metadata,
	}); err != nil {
		return domain.Item{}, err
	}
	EnqueueEmbedding(ctx, id)
	// Re-fetch the canonical item so callers see a fully-populated row
	// (artists JSON round-tripped, sources list populated).
	return ix.Repo.GetItem(ctx, id)
}
