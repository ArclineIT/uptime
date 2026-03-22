package alert

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// GotifyAlerter sends notifications to a Gotify server.
type GotifyAlerter struct {
	baseURL  string
	token    string
	priority int
	client   *http.Client
}

func NewGotifyAlerter(baseURL, token string, priority int) *GotifyAlerter {
	if priority == 0 {
		priority = 5
	}
	return &GotifyAlerter{
		baseURL:  strings.TrimRight(baseURL, "/"),
		token:    token,
		priority: priority,
		client:   &http.Client{Timeout: 10 * time.Second},
	}
}

type gotifyPayload struct {
	Title    string `json:"title"`
	Message  string `json:"message"`
	Priority int    `json:"priority"`
}

func (g *GotifyAlerter) Send(subject, body string) error {
	payload, err := json.Marshal(gotifyPayload{
		Title:    subject,
		Message:  body,
		Priority: g.priority,
	})
	if err != nil {
		return fmt.Errorf("marshal gotify payload: %w", err)
	}

	url := fmt.Sprintf("%s/message?token=%s", g.baseURL, g.token)
	resp, err := g.client.Post(url, "application/json", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("post gotify: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("gotify returned %d", resp.StatusCode)
	}
	return nil
}
