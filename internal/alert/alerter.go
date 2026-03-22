package alert

import (
	"fmt"
	"time"

	"arclineit/arcline-uptime/internal/config"
	"arclineit/arcline-uptime/internal/monitor"
)

// Alerter sends a notification with a subject and body.
type Alerter interface {
	Send(subject, body string) error
}

// NamedAlerter wraps an Alerter with its configured name for per-monitor routing.
type NamedAlerter struct {
	Name    string
	Alerter Alerter
}

// BuildNamedAlerters constructs one NamedAlerter per AlertConfig entry.
func BuildNamedAlerters(alerts []config.AlertConfig) ([]NamedAlerter, error) {
	out := make([]NamedAlerter, 0, len(alerts))
	for _, a := range alerts {
		var al Alerter
		switch a.Type {
		case "discord", "slack":
			al = NewDiscordAlerter(a.WebhookURL)
		case "email":
			al = NewEmailAlerter(a)
		case "ntfy":
			al = NewNtfyAlerter(a.URL, a.Token)
		case "gotify":
			al = NewGotifyAlerter(a.URL, a.Token, a.Priority)
		default:
			return nil, fmt.Errorf("unknown alerter type %q", a.Type)
		}
		out = append(out, NamedAlerter{Name: a.Name, Alerter: al})
	}
	return out, nil
}

// BuildAlerters is a convenience shim for callers that don't need routing.
func BuildAlerters(alerts []config.AlertConfig) ([]Alerter, error) {
	named, err := BuildNamedAlerters(alerts)
	if err != nil {
		return nil, err
	}
	out := make([]Alerter, len(named))
	for i, na := range named {
		out[i] = na.Alerter
	}
	return out, nil
}

// FormatDownMessage returns the subject and body for a failed check.
func FormatDownMessage(r monitor.Result) (subject, body string) {
	subject = fmt.Sprintf("[DOWN] %s", r.MonitorName)
	body = subject + "\n"
	if r.Error != "" {
		body += r.Error + "\n"
	}
	if r.StatusCode != 0 {
		body += fmt.Sprintf("Status code: %d\n", r.StatusCode)
	}
	body += fmt.Sprintf("Checked at %s UTC\n", r.CheckedAt.UTC().Format("2006-01-02 15:04:05"))
	body += fmt.Sprintf("Response time: %dms", r.ResponseTime.Milliseconds())
	return
}

// FormatUpMessage returns the subject and body for a recovery alert.
// downSince is the time the last DOWN alert was sent.
func FormatUpMessage(r monitor.Result, downSince time.Time) (subject, body string) {
	subject = fmt.Sprintf("[UP] %s is back up", r.MonitorName)
	body = subject + "\n"
	body += fmt.Sprintf("Was down for %s\n", FormatDuration(time.Since(downSince)))
	body += fmt.Sprintf("Recovered at %s UTC", r.CheckedAt.UTC().Format("2006-01-02 15:04:05"))
	return
}

// FormatDuration renders a duration as human-readable text, omitting leading zero units.
func FormatDuration(d time.Duration) string {
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	s := int(d.Seconds()) % 60
	if h > 0 {
		return fmt.Sprintf("%dh %dm %ds", h, m, s)
	}
	if m > 0 {
		return fmt.Sprintf("%dm %ds", m, s)
	}
	return fmt.Sprintf("%ds", s)
}
