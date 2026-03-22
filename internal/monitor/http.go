package monitor

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"arclineit/arcline-uptime/internal/config"
)

type HTTPChecker struct {
	cfg    config.MonitorConfig
	client *http.Client
}

func NewHTTPChecker(cfg config.MonitorConfig, timeout time.Duration) *HTTPChecker {
	return &HTTPChecker{
		cfg: cfg,
		client: &http.Client{
			Timeout:       timeout,
			CheckRedirect: redirectPolicy(cfg.ExpectedStatus),
		},
	}
}

// redirectPolicy stops at the first redirect when the expected status is 3xx so
// the raw redirect code is returned. Otherwise follows up to 10 redirects.
func redirectPolicy(expected int) func(*http.Request, []*http.Request) error {
	if expected >= 300 && expected < 400 {
		return func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		}
	}
	return nil
}

func (h *HTTPChecker) Name()     string        { return h.cfg.Name }
func (h *HTTPChecker) Interval() time.Duration { return time.Duration(h.cfg.Interval) * time.Second }

func (h *HTTPChecker) Check() Result {
	start := time.Now()
	result := Result{
		MonitorName: h.cfg.Name,
		CheckedAt:   start,
	}

	var bodyReader io.Reader
	if h.cfg.Body != "" {
		bodyReader = strings.NewReader(h.cfg.Body)
	}

	req, err := http.NewRequest(h.cfg.Method, h.cfg.URL, bodyReader)
	if err != nil {
		result.Error = fmt.Sprintf("build request: %v", err)
		result.ResponseTime = time.Since(start)
		return result
	}
	req.Header.Set("User-Agent", "arcline-uptime/1.0")
	for k, v := range h.cfg.Headers {
		req.Header.Set(k, v)
	}

	resp, err := h.client.Do(req)
	result.ResponseTime = time.Since(start)
	if err != nil {
		result.Error = err.Error()
		return result
	}
	defer resp.Body.Close()

	result.StatusCode = resp.StatusCode

	// Response time threshold check — before reading body to fail fast.
	applyThreshold(&result, h.cfg.MaxResponseMS)
	if !result.Up && result.Error != "" {
		return result
	}

	if resp.StatusCode != h.cfg.ExpectedStatus {
		result.Error = fmt.Sprintf("expected status %d, got %d", h.cfg.ExpectedStatus, resp.StatusCode)
		return result
	}

	if h.cfg.Contains != "" {
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		if err != nil {
			result.Error = fmt.Sprintf("read body: %v", err)
			return result
		}
		if !strings.Contains(string(body), h.cfg.Contains) {
			result.Error = fmt.Sprintf("body does not contain %q", h.cfg.Contains)
			return result
		}
	}

	result.Up = true
	applyThreshold(&result, h.cfg.MaxResponseMS)
	return result
}
