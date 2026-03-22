package scheduler

import (
	"context"
	"log/slog"
	"slices"
	"sync"
	"time"

	"arclineit/arcline-uptime/internal/alert"
	"arclineit/arcline-uptime/internal/config"
	"arclineit/arcline-uptime/internal/monitor"
	"arclineit/arcline-uptime/internal/store"
)

// Scheduler runs each monitor on its configured interval and handles alerting.
type Scheduler struct {
	checkers    []monitor.Checker
	alerters    []alert.NamedAlerter
	monitorCfgs map[string]config.MonitorConfig
	store       *store.Store
	cfg         config.GlobalConfig
	wg          sync.WaitGroup
}

func New(
	checkers []monitor.Checker,
	alerters []alert.NamedAlerter,
	monitorCfgs []config.MonitorConfig,
	s *store.Store,
	cfg config.GlobalConfig,
) *Scheduler {
	cfgMap := make(map[string]config.MonitorConfig, len(monitorCfgs))
	for _, m := range monitorCfgs {
		cfgMap[m.Name] = m
	}
	return &Scheduler{
		checkers:    checkers,
		alerters:    alerters,
		monitorCfgs: cfgMap,
		store:       s,
		cfg:         cfg,
	}
}

// Start launches one goroutine per checker plus an optional pruning goroutine.
// Each checker fires immediately, then repeats on its configured interval.
func (s *Scheduler) Start(ctx context.Context) {
	for _, c := range s.checkers {
		s.wg.Add(1)
		go func(c monitor.Checker) {
			defer s.wg.Done()
			s.runChecker(ctx, c)
		}(c)
	}

	if s.cfg.RetentionDays > 0 {
		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			s.runPruner(ctx)
		}()
	}
}

// Wait blocks until all goroutines have exited.
func (s *Scheduler) Wait() { s.wg.Wait() }

func (s *Scheduler) runChecker(ctx context.Context, c monitor.Checker) {
	interval := time.Duration(s.cfg.CheckInterval) * time.Second
	if ci := c.Interval(); ci > 0 {
		interval = ci
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		s.probe(c)
		select {
		case <-ticker.C:
		case <-ctx.Done():
			return
		}
	}
}

func (s *Scheduler) runPruner(ctx context.Context) {
	s.prune()
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			s.prune()
		case <-ctx.Done():
			return
		}
	}
}

func (s *Scheduler) prune() {
	n, err := s.store.Prune(s.cfg.RetentionDays)
	if err != nil {
		slog.Error("prune failed", "error", err)
		return
	}
	if n > 0 {
		slog.Info("pruned old records", "deleted", n, "retention_days", s.cfg.RetentionDays)
	}
}

func (s *Scheduler) probe(c monitor.Checker) {
	mcfg := s.monitorCfgs[c.Name()]

	if inMaintenanceWindow(mcfg.Maintenance) {
		slog.Debug("skipping probe: maintenance window", "monitor", c.Name())
		return
	}

	result := c.Check()

	if err := s.store.SaveResult(result); err != nil {
		slog.Error("save result", "monitor", result.MonitorName, "error", err)
	}

	s.handleAlerts(result, mcfg)

	if result.Up {
		slog.Info("check ok", "monitor", result.MonitorName, "ms", result.ResponseTime.Milliseconds())
	} else {
		slog.Warn("check failed", "monitor", result.MonitorName, "error", result.Error)
	}
}

func (s *Scheduler) handleAlerts(r monitor.Result, mcfg config.MonitorConfig) {
	cooldown := time.Duration(s.cfg.AlertCooldown) * time.Second

	if !r.Up {
		lastDown, err := s.store.LastAlertSent(r.MonitorName, "down")
		if err != nil {
			slog.Error("query last-down alert", "monitor", r.MonitorName, "error", err)
			return
		}
		if lastDown.IsZero() || time.Since(lastDown) >= cooldown {
			subject, body := alert.FormatDownMessage(r)
			s.sendRouted(mcfg, "down", subject, body)
		}
		return
	}

	// Monitor is up — send recovery if the last alert was a down.
	lastDown, err := s.store.LastAlertSent(r.MonitorName, "down")
	if err != nil {
		slog.Error("query last-down alert", "monitor", r.MonitorName, "error", err)
		return
	}
	if lastDown.IsZero() {
		return
	}
	lastUp, err := s.store.LastAlertSent(r.MonitorName, "up")
	if err != nil {
		slog.Error("query last-up alert", "monitor", r.MonitorName, "error", err)
		return
	}
	if lastUp.Before(lastDown) {
		subject, body := alert.FormatUpMessage(r, lastDown)
		s.sendRouted(mcfg, "up", subject, body)
		slog.Info("recovery alert sent", "monitor", r.MonitorName,
			"down_duration", alert.FormatDuration(time.Since(lastDown)))
	}
}

// sendRouted sends to alerters matching the monitor's alert_names filter.
// If alert_names is empty, sends to all alerters.
func (s *Scheduler) sendRouted(mcfg config.MonitorConfig, kind, subject, body string) {
	for _, na := range s.alerters {
		if len(mcfg.AlertNames) > 0 && !slices.Contains(mcfg.AlertNames, na.Name) {
			continue
		}
		if err := na.Alerter.Send(subject, body); err != nil {
			slog.Error("send alert", "kind", kind, "monitor", mcfg.Name, "alerter", na.Name, "error", err)
		}
	}
	if err := s.store.RecordAlertSent(mcfg.Name, kind); err != nil {
		slog.Error("record alert", "monitor", mcfg.Name, "error", err)
	}
}

// inMaintenanceWindow reports whether any window in the list is currently active.
func inMaintenanceWindow(windows []config.MaintenanceWindow) bool {
	now := time.Now()
	for i := range windows {
		if windows[i].Active(now) {
			return true
		}
	}
	return false
}
