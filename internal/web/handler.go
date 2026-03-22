package web

import (
	"crypto/subtle"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"arclineit/arcline-uptime/internal/config"
	"arclineit/arcline-uptime/internal/store"
)

// MonitorStatus is the view model for the main dashboard page.
type MonitorStatus struct {
	Name       string
	Up         bool
	StatusCode int
	ResponseMS int64
	Error      string
	CheckedAt  time.Time
	Uptime24h  float64
	Uptime7d   float64
	Uptime30d  float64
}

// SparklineData is the view model for the history page.
type SparklineData struct {
	Name       string
	Points     string // SVG polyline points for all checks
	DownDotXs  []int  // X coordinates of failed checks (rendered as red dots at y=55)
	MaxMS      int64
	AvgMS      float64
	Count      int
}

// IncidentView is the view model for the incidents page.
type IncidentView struct {
	MonitorName string
	StartedAt   time.Time
	ResolvedAt  time.Time
	Duration    string
	Ongoing     bool
}

// NewServer creates the HTTP server for the dashboard.
func NewServer(cfg *config.Config, s *store.Store) *http.Server {
	h := &handler{store: s, cfg: cfg}

	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", h.handleMetrics)       // no auth — Prometheus scraping
	mux.HandleFunc("/status", h.handlePublicStatus)   // no auth — public status page
	mux.HandleFunc("/incidents", h.auth(h.handleIncidents))
	mux.HandleFunc("/history", h.auth(h.handleHistory))
	mux.HandleFunc("/", h.auth(h.handleIndex))

	return &http.Server{
		Addr:    cfg.Dashboard.Listen,
		Handler: mux,
	}
}

type handler struct {
	store *store.Store
	cfg   *config.Config
}

// auth wraps a handler with HTTP Basic Auth if credentials are configured.
func (h *handler) auth(next http.HandlerFunc) http.HandlerFunc {
	if h.cfg.Dashboard.Username == "" {
		return next
	}
	return func(w http.ResponseWriter, r *http.Request) {
		user, pass, ok := r.BasicAuth()
		userOK := subtle.ConstantTimeCompare([]byte(user), []byte(h.cfg.Dashboard.Username))
		passOK := subtle.ConstantTimeCompare([]byte(pass), []byte(h.cfg.Dashboard.Password))
		if !ok || userOK != 1 || passOK != 1 {
			w.Header().Set("WWW-Authenticate", `Basic realm="arcline-uptime"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// --- Route Handlers ---

func (h *handler) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	names := h.monitorNames()
	now := time.Now()

	statuses := make([]MonitorStatus, 0, len(names))
	for _, name := range names {
		ms := MonitorStatus{Name: name}
		if row, err := h.store.LatestResult(name); err == nil && row != nil {
			ms.Up = row.Up
			ms.StatusCode = row.StatusCode
			ms.ResponseMS = row.ResponseMS
			ms.Error = row.Error
			ms.CheckedAt = row.CheckedAt
		}
		ms.Uptime24h, _ = h.store.UptimePercent(name, now.Add(-24*time.Hour))
		ms.Uptime7d, _ = h.store.UptimePercent(name, now.AddDate(0, 0, -7))
		ms.Uptime30d, _ = h.store.UptimePercent(name, now.AddDate(0, 0, -30))
		statuses = append(statuses, ms)
	}

	data := struct {
		Now      time.Time
		Monitors []MonitorStatus
	}{Now: now.UTC(), Monitors: statuses}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := indexTmpl.Execute(w, data); err != nil {
		slog.Error("render index", "error", err)
	}
}

func (h *handler) handleHistory(w http.ResponseWriter, r *http.Request) {
	names := h.monitorNames()

	sparklines := make([]SparklineData, 0, len(names))
	for _, name := range names {
		rows, err := h.store.RecentChecks(name, 100)
		if err != nil {
			slog.Error("fetch history", "monitor", name, "error", err)
			continue
		}
		sparklines = append(sparklines, buildSparkline(name, rows))
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := historyTmpl.Execute(w, sparklines); err != nil {
		slog.Error("render history", "error", err)
	}
}

func (h *handler) handleIncidents(w http.ResponseWriter, r *http.Request) {
	incidents, err := h.store.Incidents(100)
	if err != nil {
		slog.Error("fetch incidents", "error", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	views := make([]IncidentView, 0, len(incidents))
	for _, inc := range incidents {
		v := IncidentView{
			MonitorName: inc.MonitorName,
			StartedAt:   inc.StartedAt,
			ResolvedAt:  inc.ResolvedAt,
			Ongoing:     inc.Ongoing(),
		}
		if !inc.Ongoing() {
			v.Duration = formatDuration(inc.Duration())
		} else {
			v.Duration = formatDuration(inc.Duration()) + " (ongoing)"
		}
		views = append(views, v)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := incidentsTmpl.Execute(w, views); err != nil {
		slog.Error("render incidents", "error", err)
	}
}

func (h *handler) handlePublicStatus(w http.ResponseWriter, r *http.Request) {
	names := h.monitorNames()
	now := time.Now()

	type publicStatus struct {
		Name      string
		Up        bool
		Uptime24h float64
	}

	statuses := make([]publicStatus, 0, len(names))
	allUp := true
	for _, name := range names {
		ps := publicStatus{Name: name}
		if row, err := h.store.LatestResult(name); err == nil && row != nil {
			ps.Up = row.Up
			if !row.Up {
				allUp = false
			}
		}
		ps.Uptime24h, _ = h.store.UptimePercent(name, now.Add(-24*time.Hour))
		statuses = append(statuses, ps)
	}

	data := struct {
		AllUp    bool
		Monitors []publicStatus
		UpdatedAt time.Time
	}{AllUp: allUp, Monitors: statuses, UpdatedAt: now.UTC()}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := statusTmpl.Execute(w, data); err != nil {
		slog.Error("render status", "error", err)
	}
}

func (h *handler) handleMetrics(w http.ResponseWriter, r *http.Request) {
	names := h.monitorNames()
	now := time.Now()

	var sb strings.Builder
	sb.WriteString("# HELP arcline_uptime_up Whether the last check succeeded (1=up, 0=down)\n")
	sb.WriteString("# TYPE arcline_uptime_up gauge\n")
	for _, name := range names {
		val := 0
		if row, err := h.store.LatestResult(name); err == nil && row != nil && row.Up {
			val = 1
		}
		fmt.Fprintf(&sb, "arcline_uptime_up{monitor=%q} %d\n", name, val)
	}

	sb.WriteString("# HELP arcline_uptime_response_ms Response time of the last check in milliseconds\n")
	sb.WriteString("# TYPE arcline_uptime_response_ms gauge\n")
	for _, name := range names {
		var ms int64
		if row, err := h.store.LatestResult(name); err == nil && row != nil {
			ms = row.ResponseMS
		}
		fmt.Fprintf(&sb, "arcline_uptime_response_ms{monitor=%q} %d\n", name, ms)
	}

	sb.WriteString("# HELP arcline_uptime_uptime_24h Uptime percentage over the last 24 hours\n")
	sb.WriteString("# TYPE arcline_uptime_uptime_24h gauge\n")
	for _, name := range names {
		pct, _ := h.store.UptimePercent(name, now.Add(-24*time.Hour))
		fmt.Fprintf(&sb, "arcline_uptime_uptime_24h{monitor=%q} %.4f\n", name, pct)
	}

	sb.WriteString("# HELP arcline_uptime_uptime_7d Uptime percentage over the last 7 days\n")
	sb.WriteString("# TYPE arcline_uptime_uptime_7d gauge\n")
	for _, name := range names {
		pct, _ := h.store.UptimePercent(name, now.AddDate(0, 0, -7))
		fmt.Fprintf(&sb, "arcline_uptime_uptime_7d{monitor=%q} %.4f\n", name, pct)
	}

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	fmt.Fprint(w, sb.String())
}

// monitorNames returns configured monitors first (in order), then any DB-only names.
func (h *handler) monitorNames() []string {
	seen := make(map[string]bool)
	var names []string
	for _, m := range h.cfg.Monitors {
		if !seen[m.Name] {
			seen[m.Name] = true
			names = append(names, m.Name)
		}
	}
	if dbNames, err := h.store.AllMonitorNames(); err == nil {
		for _, n := range dbNames {
			if !seen[n] {
				seen[n] = true
				names = append(names, n)
			}
		}
	}
	return names
}

// buildSparkline converts a slice of CheckRows into SVG data.
// Rows are expected newest-first; they are reversed to plot oldest→newest left→right.
func buildSparkline(name string, rows []store.CheckRow) SparklineData {
	sd := SparklineData{Name: name}
	if len(rows) == 0 {
		return sd
	}

	n := len(rows)
	rev := make([]store.CheckRow, n)
	for i, r := range rows {
		rev[n-1-i] = r
	}

	var total, maxMS int64
	for i, r := range rev {
		total += r.ResponseMS
		if r.ResponseMS > maxMS {
			maxMS = r.ResponseMS
		}
		x := 0
		if n > 1 {
			x = i * 400 / (n - 1)
		}
		if !r.Up {
			sd.DownDotXs = append(sd.DownDotXs, x)
		}
	}
	sd.MaxMS = maxMS
	sd.AvgMS = float64(total) / float64(n)
	sd.Count = n

	const (
		svgW    = 400
		svgH    = 60
		padding = 5
	)

	var pts strings.Builder
	for i, r := range rev {
		x := 0
		if n > 1 {
			x = i * svgW / (n - 1)
		}
		var y int
		if maxMS > 0 {
			norm := float64(r.ResponseMS) / float64(maxMS)
			y = padding + int((1.0-norm)*float64(svgH-2*padding))
		} else {
			y = svgH - padding
		}
		fmt.Fprintf(&pts, "%d,%d ", x, y)
	}
	sd.Points = strings.TrimSpace(pts.String())
	return sd
}

func formatDuration(d time.Duration) string {
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
