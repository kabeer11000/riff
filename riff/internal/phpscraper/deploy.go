package phpscraper

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// deployResponse mirrors updater.php's JSON reply.
type deployResponse struct {
	OK    bool   `json:"ok"`
	File  string `json:"file"`
	Bytes int    `json:"bytes"`
	Error string `json:"error"`
}

// Deploy pushes content to updater.php, which writes it to filename inside
// the relay's own directory. token must match the relay's
// updater-secret.php. Goes through the same challenge-solving transport as
// reads, so it reuses whatever cookie the client already cached.
func (c *Client) Deploy(ctx context.Context, token, filename, content string) error {
	body, err := c.postForm(ctx, "/updater.php", url.Values{
		"name":    {filename},
		"content": {content},
	}, map[string]string{"X-Updater-Token": token})
	if err != nil {
		return err
	}
	var res deployResponse
	if err := json.Unmarshal(body, &res); err != nil {
		return fmt.Errorf("phpscraper: deploy response decode: %w (body: %s)", err, truncate(body, 300))
	}
	if !res.OK {
		return fmt.Errorf("phpscraper: deploy of %s rejected: %s", filename, res.Error)
	}
	return nil
}

func truncate(b []byte, n int) string {
	if len(b) <= n {
		return string(b)
	}
	return string(b[:n]) + "..."
}
