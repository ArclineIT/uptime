package alert

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type DiscordAlerter struct {
	webhookURL string
	client     *http.Client
}

func NewDiscordAlerter(webhookURL string) *DiscordAlerter {
	return &DiscordAlerter{
		webhookURL: webhookURL,
		client:     &http.Client{Timeout: 10 * time.Second},
	}
}

func (d *DiscordAlerter) Send(subject, body string) error {
	payload, err := json.Marshal(map[string]string{"content": body})
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	resp, err := d.client.Post(d.webhookURL, "application/json", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("post webhook: %w", err)
	}
	defer resp.Body.Close()

	// Discord returns 204 No Content on success.
	if resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("webhook returned %d", resp.StatusCode)
	}
	return nil
}
