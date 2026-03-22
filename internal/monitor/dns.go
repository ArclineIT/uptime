package monitor

import (
	"context"
	"fmt"
	"net"
	"time"

	"arclineit/arcline-uptime/internal/config"
)

// DNSChecker resolves a hostname and optionally asserts a specific IP is returned.
type DNSChecker struct {
	cfg     config.MonitorConfig
	timeout time.Duration
}

func NewDNSChecker(cfg config.MonitorConfig, timeout time.Duration) *DNSChecker {
	return &DNSChecker{cfg: cfg, timeout: timeout}
}

func (d *DNSChecker) Name()     string        { return d.cfg.Name }
func (d *DNSChecker) Interval() time.Duration { return time.Duration(d.cfg.Interval) * time.Second }

func (d *DNSChecker) Check() Result {
	start := time.Now()
	result := Result{
		MonitorName: d.cfg.Name,
		CheckedAt:   start,
	}

	ctx, cancel := context.WithTimeout(context.Background(), d.timeout)
	defer cancel()

	addrs, err := net.DefaultResolver.LookupHost(ctx, d.cfg.Host)
	result.ResponseTime = time.Since(start)
	if err != nil {
		result.Error = err.Error()
		return result
	}

	if d.cfg.ExpectedIP != "" {
		want := normalizeIP(d.cfg.ExpectedIP)
		found := false
		for _, addr := range addrs {
			if normalizeIP(addr) == want {
				found = true
				break
			}
		}
		if !found {
			result.Error = fmt.Sprintf("expected IP %q not found in results %v", d.cfg.ExpectedIP, addrs)
			return result
		}
	}

	result.Up = true
	applyThreshold(&result, d.cfg.MaxResponseMS)
	return result
}

// normalizeIP parses and re-serialises an IP string so different representations
// of the same address compare equal (e.g. "::1" and "0:0:0:0:0:0:0:1").
func normalizeIP(s string) string {
	if ip := net.ParseIP(s); ip != nil {
		return ip.String()
	}
	return s
}
