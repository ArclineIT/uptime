package alert

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

// NtfyAlerter sends notifications via ntfy.sh or a self-hosted ntfy server.
// The URL should be the full topic URL, e.g. "https://ntfy.sh/my-topic".
type NtfyAlerter struct {
	url    string
	token  string // optional Bearer token
	client *http.Client
}

func NewNtfyAlerter(url, token string) *NtfyAlerter {
	return &NtfyAlerter{
		url:    url,
		token:  token,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

func (n *NtfyAlerter) Send(subject, body string) error {
	req, err := http.NewRequest(http.MethodPost, n.url, strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("build ntfy request: %w", err)
	}
	req.Header.Set("Content-Type", "text/plain")
	req.Header.Set("Title", subject)
	if n.token != "" {
		req.Header.Set("Authorization", "Bearer "+n.token)
	}

	resp, err := n.client.Do(req)
	if err != nil {
		return fmt.Errorf("post ntfy: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("ntfy returned %d", resp.StatusCode)
	}
	return nil
}
