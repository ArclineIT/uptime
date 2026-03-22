package monitor

import (
	"fmt"
	"net"
	"time"

	"arclineit/arcline-uptime/internal/config"
)

type TCPChecker struct {
	cfg     config.MonitorConfig
	addr    string
	timeout time.Duration
}

func NewTCPChecker(cfg config.MonitorConfig, timeout time.Duration) *TCPChecker {
	return &TCPChecker{
		cfg:     cfg,
		addr:    fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		timeout: timeout,
	}
}

func (t *TCPChecker) Name()     string        { return t.cfg.Name }
func (t *TCPChecker) Interval() time.Duration { return time.Duration(t.cfg.Interval) * time.Second }

func (t *TCPChecker) Check() Result {
	start := time.Now()
	result := Result{
		MonitorName: t.cfg.Name,
		CheckedAt:   start,
	}

	conn, err := net.DialTimeout("tcp", t.addr, t.timeout)
	result.ResponseTime = time.Since(start)
	if err != nil {
		result.Error = err.Error()
		return result
	}
	conn.Close()

	result.Up = true
	applyThreshold(&result, t.cfg.MaxResponseMS)
	return result
}
