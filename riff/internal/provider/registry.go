package provider

import (
	"context"
	"sync"
)

// Registry fans out searches across all providers and merges results.
type Registry struct {
	Providers []Provider
}

func (r *Registry) Get(name string) Provider {
	for _, p := range r.Providers {
		if p.Name() == name {
			return p
		}
	}
	return nil
}

// SearchAll runs every provider in parallel and concatenates the results.
// Dedup happens at indexing time (sources table is the dedup boundary), so
// here we just merge.
func (r *Registry) SearchAll(ctx context.Context, query string, limit int) ([]Result, error) {
	if len(r.Providers) == 0 {
		return nil, nil
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	var out []Result
	var firstErr error
	for _, p := range r.Providers {
		wg.Add(1)
		go func(p Provider) {
			defer wg.Done()
			hits, err := p.Search(ctx, query, limit)
			if err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				return
			}
			mu.Lock()
			out = append(out, hits...)
			mu.Unlock()
		}(p)
	}
	wg.Wait()
	return out, firstErr
}
