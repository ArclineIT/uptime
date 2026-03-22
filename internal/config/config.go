package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Global    GlobalConfig    `yaml:"global"`
	Alerts    []AlertConfig   `yaml:"alerts"`
	Monitors  []MonitorConfig `yaml:"monitors"`
	Dashboard DashboardConfig `yaml:"dashboard"`
}

type GlobalConfig struct {
	CheckInterval int    `yaml:"check_interval"` // seconds
	Timeout       int    `yaml:"timeout"`         // seconds
	AlertCooldown int    `yaml:"alert_cooldown"`  // seconds
	RetentionDays int    `yaml:"retention_days"`  // 0 = keep forever
	LogFormat     string `yaml:"log_format"`      // "text" (default) | "json"
}

// StringSlice accepts either a single YAML string or a YAML sequence.
type StringSlice []string

func (s *StringSlice) UnmarshalYAML(value *yaml.Node) error {
	if value.Kind == yaml.ScalarNode {
		*s = StringSlice{value.Value}
		return nil
	}
	var strs []string
	if err := value.Decode(&strs); err != nil {
		return err
	}
	*s = strs
	return nil
}

type AlertConfig struct {
	Name       string      `yaml:"name"`        // optional; used for per-monitor routing
	Type       string      `yaml:"type"`        // "discord" | "slack" | "email" | "ntfy" | "gotify"
	WebhookURL string      `yaml:"webhook_url"` // discord / slack
	SMTPHost   string      `yaml:"smtp_host"`
	SMTPPort   int         `yaml:"smtp_port"`
	From       string      `yaml:"from"`
	To         StringSlice `yaml:"to"` // one or more email addresses
	Username   string      `yaml:"username"`
	Password   string      `yaml:"password"`
	URL        string      `yaml:"url"`      // ntfy topic URL or gotify server base URL
	Token      string      `yaml:"token"`    // ntfy bearer token or gotify app token
	Priority   int         `yaml:"priority"` // gotify priority; default 5
}

// MaintenanceWindow suppresses alerts during a recurring time range.
type MaintenanceWindow struct {
	Days  []string `yaml:"days"`  // abbreviated weekday names ("mon"…"sun"), or "*" for all
	Start string   `yaml:"start"` // "HH:MM" in server local time
	End   string   `yaml:"end"`   // "HH:MM"
}

// Active reports whether the window covers t.
func (w *MaintenanceWindow) Active(t time.Time) bool {
	if len(w.Days) > 0 {
		day := strings.ToLower(t.Weekday().String()[:3])
		found := false
		for _, d := range w.Days {
			if d == "*" || strings.ToLower(d) == day {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	startH, startM, err1 := parseHHMM(w.Start)
	endH, endM, err2 := parseHHMM(w.End)
	if err1 != nil || err2 != nil {
		return false
	}
	now := t.Hour()*60 + t.Minute()
	start := startH*60 + startM
	end := endH*60 + endM
	if start <= end {
		return now >= start && now < end
	}
	// Crosses midnight (e.g. 23:00–02:00)
	return now >= start || now < end
}

func parseHHMM(s string) (int, int, error) {
	parts := strings.SplitN(s, ":", 2)
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid time %q", s)
	}
	h, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, 0, err
	}
	m, err := strconv.Atoi(parts[1])
	if err != nil {
		return 0, 0, err
	}
	return h, m, nil
}

type MonitorConfig struct {
	Name    string `yaml:"name"`
	Type    string `yaml:"type"` // "http" | "tcp" | "tls" | "dns"

	// HTTP
	URL            string            `yaml:"url"`
	Method         string            `yaml:"method"`          // default "GET"
	Body           string            `yaml:"body"`
	Headers        map[string]string `yaml:"headers"`
	ExpectedStatus int               `yaml:"expected_status"` // default 200
	Contains       string            `yaml:"contains"`

	// TCP / TLS / DNS
	Host string `yaml:"host"`
	Port int    `yaml:"port"`

	// TLS
	ExpiryWarningDays int `yaml:"expiry_warning_days"` // default 14

	// DNS
	ExpectedIP string `yaml:"expected_ip"` // optional; assert resolved IPs include this

	// Thresholds
	MaxResponseMS int64 `yaml:"max_response_ms"` // 0 = no threshold

	// Per-monitor scheduling
	Interval int `yaml:"interval"` // seconds; 0 = global default
	Timeout  int `yaml:"timeout"`  // seconds; 0 = global default

	// Alerting
	AlertNames  []string            `yaml:"alert_names"` // empty = all alerters
	Maintenance []MaintenanceWindow `yaml:"maintenance"`
}

type DashboardConfig struct {
	Enabled  bool   `yaml:"enabled"`
	Listen   string `yaml:"listen"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	applyDefaults(&cfg)
	if err := validate(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func applyDefaults(cfg *Config) {
	if cfg.Global.CheckInterval == 0 {
		cfg.Global.CheckInterval = 60
	}
	if cfg.Global.Timeout == 0 {
		cfg.Global.Timeout = 10
	}
	if cfg.Global.AlertCooldown == 0 {
		cfg.Global.AlertCooldown = 300
	}
	if cfg.Global.LogFormat == "" {
		cfg.Global.LogFormat = "text"
	}
	if cfg.Dashboard.Listen == "" {
		cfg.Dashboard.Listen = ":8081"
	}
	for i := range cfg.Monitors {
		m := &cfg.Monitors[i]
		if m.Type == "http" {
			if m.ExpectedStatus == 0 {
				m.ExpectedStatus = 200
			}
			if m.Method == "" {
				m.Method = "GET"
			}
		}
		if m.Type == "tls" {
			if m.ExpiryWarningDays == 0 {
				m.ExpiryWarningDays = 14
			}
			if m.Port == 0 {
				m.Port = 443
			}
		}
		if m.Interval == 0 {
			m.Interval = cfg.Global.CheckInterval
		}
		if m.Timeout == 0 {
			m.Timeout = cfg.Global.Timeout
		}
	}
	for i := range cfg.Alerts {
		if cfg.Alerts[i].Type == "gotify" && cfg.Alerts[i].Priority == 0 {
			cfg.Alerts[i].Priority = 5
		}
	}
}

func validate(cfg *Config) error {
	names := make(map[string]bool)
	for _, m := range cfg.Monitors {
		if m.Name == "" {
			return fmt.Errorf("monitor missing name")
		}
		if names[m.Name] {
			return fmt.Errorf("duplicate monitor name: %q", m.Name)
		}
		names[m.Name] = true
		switch m.Type {
		case "http":
			if m.URL == "" {
				return fmt.Errorf("monitor %q: missing url", m.Name)
			}
		case "tcp", "tls":
			if m.Host == "" || m.Port == 0 {
				return fmt.Errorf("monitor %q: missing host or port", m.Name)
			}
		case "dns":
			if m.Host == "" {
				return fmt.Errorf("monitor %q: missing host", m.Name)
			}
		default:
			return fmt.Errorf("monitor %q: unknown type %q", m.Name, m.Type)
		}
	}

	// Build set of named alerters to validate monitor alert_names references.
	alertNames := make(map[string]bool)
	for _, a := range cfg.Alerts {
		if a.Name != "" {
			alertNames[a.Name] = true
		}
	}
	for _, m := range cfg.Monitors {
		for _, an := range m.AlertNames {
			if !alertNames[an] {
				return fmt.Errorf("monitor %q: alert_name %q not defined", m.Name, an)
			}
		}
	}
	return nil
}
