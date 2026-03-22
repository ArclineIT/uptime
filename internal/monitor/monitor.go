package monitor

import (
	"fmt"
	"time"

	"arclineit/arcline-uptime/internal/config"
)

// Result is returned by every Checker after a single probe.
type Result struct {
	MonitorName  string
	Up           bool
	StatusCode   int // HTTP only; 0 for TCP/TLS/DNS
	ResponseTime time.Duration
	Error        string    // empty when Up == true
	CheckedAt    time.Time
}

// Checker probes one endpoint.
type Checker interface {
	Name()     string
	Check()    Result
	Interval() time.Duration // per-monitor interval; 0 means use the global default
}

// BuildCheckers constructs one Checker per MonitorConfig entry.
// globalTimeout is the fallback when a monitor's own Timeout is 0.
func BuildCheckers(monitors []config.MonitorConfig, globalTimeout time.Duration) ([]Checker, error) {
	checkers := make([]Checker, 0, len(monitors))
	for _, m := range monitors {
		timeout := globalTimeout
		if m.Timeout > 0 {
			timeout = time.Duration(m.Timeout) * time.Second
		}
		switch m.Type {
		case "http":
			checkers = append(checkers, NewHTTPChecker(m, timeout))
		case "tcp":
			checkers = append(checkers, NewTCPChecker(m, timeout))
		case "tls":
			checkers = append(checkers, NewTLSChecker(m, timeout))
		case "dns":
			checkers = append(checkers, NewDNSChecker(m, timeout))
		default:
			return nil, fmt.Errorf("unknown monitor type %q for %q", m.Type, m.Name)
		}
	}
	return checkers, nil
}

// applyThreshold marks a successful result as failed if response time exceeds max.
func applyThreshold(r *Result, maxResponseMS int64) {
	if maxResponseMS > 0 && r.Up && r.ResponseTime.Milliseconds() > maxResponseMS {
		r.Up = false
		r.Error = fmt.Sprintf("response time %dms exceeded threshold %dms",
			r.ResponseTime.Milliseconds(), maxResponseMS)
	}
}
