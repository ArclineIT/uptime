package monitor

import (
	"crypto/tls"
	"fmt"
	"net"
	"time"

	"arclineit/arcline-uptime/internal/config"
)

// TLSChecker dials a TLS endpoint and alerts when the certificate is about
// to expire (within ExpiryWarningDays days).
type TLSChecker struct {
	cfg     config.MonitorConfig
	timeout time.Duration
}

func NewTLSChecker(cfg config.MonitorConfig, timeout time.Duration) *TLSChecker {
	return &TLSChecker{cfg: cfg, timeout: timeout}
}

func (t *TLSChecker) Name()     string        { return t.cfg.Name }
func (t *TLSChecker) Interval() time.Duration { return time.Duration(t.cfg.Interval) * time.Second }

func (t *TLSChecker) Check() Result {
	start := time.Now()
	result := Result{
		MonitorName: t.cfg.Name,
		CheckedAt:   start,
	}

	addr := fmt.Sprintf("%s:%d", t.cfg.Host, t.cfg.Port)
	dialer := &tls.Dialer{
		NetDialer: &net.Dialer{Timeout: t.timeout},
		Config:    &tls.Config{ServerName: t.cfg.Host},
	}

	conn, err := dialer.Dial("tcp", addr)
	result.ResponseTime = time.Since(start)
	if err != nil {
		result.Error = err.Error()
		return result
	}
	defer conn.Close()

	tlsConn := conn.(*tls.Conn)
	state := tlsConn.ConnectionState()

	// Find the earliest-expiring certificate in the chain.
	var earliest time.Time
	for _, cert := range state.PeerCertificates {
		if earliest.IsZero() || cert.NotAfter.Before(earliest) {
			earliest = cert.NotAfter
		}
	}

	daysLeft := int(time.Until(earliest).Hours() / 24)
	if daysLeft <= t.cfg.ExpiryWarningDays {
		result.Error = fmt.Sprintf("certificate expires in %d day(s) on %s",
			daysLeft, earliest.UTC().Format("2006-01-02"))
		return result
	}

	result.Up = true
	applyThreshold(&result, t.cfg.MaxResponseMS)
	return result
}
