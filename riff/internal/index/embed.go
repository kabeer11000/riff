package index

import (
	"context"
	"log/slog"
)

// EnqueueEmbedding is a hook for the recd recommendation service. recd will
// later consume embeddings from a Redis queue and store them in the same
// Turso DB; today this just logs so we can confirm the call site is exercised
// during smoke tests.
func EnqueueEmbedding(ctx context.Context, itemID string) {
	slog.Info("embed:enqueue", "item", itemID)
}
