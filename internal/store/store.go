package store

import (
	"database/sql"
	"fmt"
	"sort"
	"time"

	_ "modernc.org/sqlite"

	"arclineit/arcline-uptime/internal/monitor"
)

// Store wraps the SQLite database.
type Store struct {
	db *sql.DB
}

// CheckRow is a row read back from the checks table.
type CheckRow struct {
	ID          int64
	MonitorName string
	CheckedAt   time.Time
	Up          bool
	StatusCode  int
	ResponseMS  int64
	Error       string
}

// AlertRow is a row from the alerts_sent table.
type AlertRow struct {
	ID          int64
	MonitorName string
	SentAt      time.Time
	Kind        string // "down" | "up"
}

// Incident represents a period during which a monitor was down.
type Incident struct {
	MonitorName string
	StartedAt   time.Time
	ResolvedAt  time.Time // zero if still ongoing
}

func (i Incident) Duration() time.Duration {
	if i.ResolvedAt.IsZero() {
		return time.Since(i.StartedAt)
	}
	return i.ResolvedAt.Sub(i.StartedAt)
}

func (i Incident) Ongoing() bool { return i.ResolvedAt.IsZero() }

// Open opens (or creates) the SQLite database at path and migrates the schema.
func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	// SQLite does not support concurrent writers; serialise through one connection.
	db.SetMaxOpenConns(1)

	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	_, err := s.db.Exec(`
		CREATE TABLE IF NOT EXISTS checks (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			monitor_name TEXT    NOT NULL,
			checked_at   INTEGER NOT NULL,
			up           INTEGER NOT NULL,
			status_code  INTEGER NOT NULL DEFAULT 0,
			response_ms  INTEGER NOT NULL DEFAULT 0,
			error        TEXT    NOT NULL DEFAULT ''
		);
		CREATE INDEX IF NOT EXISTS idx_checks_monitor_time
			ON checks (monitor_name, checked_at DESC);

		CREATE TABLE IF NOT EXISTS alerts_sent (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			monitor_name TEXT    NOT NULL,
			sent_at      INTEGER NOT NULL,
			kind         TEXT    NOT NULL
		);
		CREATE INDEX IF NOT EXISTS idx_alerts_monitor
			ON alerts_sent (monitor_name, sent_at DESC);
	`)
	return err
}

// --- Writes ---

// SaveResult persists one check result.
func (s *Store) SaveResult(r monitor.Result) error {
	_, err := s.db.Exec(
		`INSERT INTO checks (monitor_name, checked_at, up, status_code, response_ms, error)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		r.MonitorName,
		r.CheckedAt.Unix(),
		boolToInt(r.Up),
		r.StatusCode,
		r.ResponseTime.Milliseconds(),
		r.Error,
	)
	return err
}

// RecordAlertSent writes a row indicating an alert of kind ("down"|"up") was sent.
func (s *Store) RecordAlertSent(monitorName, kind string) error {
	_, err := s.db.Exec(
		`INSERT INTO alerts_sent (monitor_name, sent_at, kind) VALUES (?, ?, ?)`,
		monitorName, time.Now().Unix(), kind,
	)
	return err
}

// Prune deletes check and alert rows older than retentionDays.
func (s *Store) Prune(retentionDays int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -retentionDays).Unix()
	res, err := s.db.Exec(`DELETE FROM checks WHERE checked_at < ?`, cutoff)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()

	res2, err := s.db.Exec(`DELETE FROM alerts_sent WHERE sent_at < ?`, cutoff)
	if err != nil {
		return n, err
	}
	n2, _ := res2.RowsAffected()
	return n + n2, nil
}

// --- Single-monitor reads ---

// LatestResult returns the most recent check for the given monitor, or nil if none.
func (s *Store) LatestResult(monitorName string) (*CheckRow, error) {
	row := s.db.QueryRow(
		`SELECT id, monitor_name, checked_at, up, status_code, response_ms, error
		 FROM checks WHERE monitor_name = ? ORDER BY checked_at DESC LIMIT 1`,
		monitorName,
	)
	return scanCheckRow(row)
}

// LastAlertSent returns the time of the most recent alert of the given kind.
// Returns zero time if no such alert exists.
func (s *Store) LastAlertSent(monitorName, kind string) (time.Time, error) {
	var ts int64
	err := s.db.QueryRow(
		`SELECT sent_at FROM alerts_sent WHERE monitor_name = ? AND kind = ?
		 ORDER BY sent_at DESC LIMIT 1`,
		monitorName, kind,
	).Scan(&ts)
	if err == sql.ErrNoRows {
		return time.Time{}, nil
	}
	if err != nil {
		return time.Time{}, err
	}
	return time.Unix(ts, 0), nil
}

// RecentChecks returns the most recent limit checks for a monitor, newest first.
func (s *Store) RecentChecks(monitorName string, limit int) ([]CheckRow, error) {
	rows, err := s.db.Query(
		`SELECT id, monitor_name, checked_at, up, status_code, response_ms, error
		 FROM checks WHERE monitor_name = ? ORDER BY checked_at DESC LIMIT ?`,
		monitorName, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []CheckRow
	for rows.Next() {
		r, err := scanCheckRowFromRows(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *r)
	}
	return out, rows.Err()
}

// UptimePercent returns the percentage of successful checks since `since`.
// Returns 100.0 if no checks exist yet.
func (s *Store) UptimePercent(monitorName string, since time.Time) (float64, error) {
	var total, upCount int64
	err := s.db.QueryRow(
		`SELECT COUNT(*), COALESCE(SUM(up), 0)
		 FROM checks WHERE monitor_name = ? AND checked_at >= ?`,
		monitorName, since.Unix(),
	).Scan(&total, &upCount)
	if err != nil {
		return 0, err
	}
	if total == 0 {
		return 100.0, nil
	}
	return float64(upCount) / float64(total) * 100.0, nil
}

// --- Multi-monitor reads ---

// AllMonitorNames returns all distinct monitor names that have check records.
func (s *Store) AllMonitorNames() ([]string, error) {
	rows, err := s.db.Query(`SELECT DISTINCT monitor_name FROM checks ORDER BY monitor_name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, rows.Err()
}

// AlertsSent returns all alert rows since `since`, ordered oldest-first.
func (s *Store) AlertsSent(since time.Time) ([]AlertRow, error) {
	rows, err := s.db.Query(
		`SELECT id, monitor_name, sent_at, kind FROM alerts_sent
		 WHERE sent_at >= ? ORDER BY monitor_name, sent_at ASC`,
		since.Unix(),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AlertRow
	for rows.Next() {
		var a AlertRow
		var ts int64
		if err := rows.Scan(&a.ID, &a.MonitorName, &ts, &a.Kind); err != nil {
			return nil, err
		}
		a.SentAt = time.Unix(ts, 0)
		out = append(out, a)
	}
	return out, rows.Err()
}

// Incidents pairs down/up alert rows into Incident structs, sorted newest-first.
// Ongoing incidents (no matching up alert) are included with a zero ResolvedAt.
func (s *Store) Incidents(limit int) ([]Incident, error) {
	rows, err := s.AlertsSent(time.Time{}) // all time
	if err != nil {
		return nil, err
	}

	type openIncident struct{ start time.Time }
	open := make(map[string]*openIncident)
	var incidents []Incident

	for _, a := range rows {
		switch a.Kind {
		case "down":
			if _, already := open[a.MonitorName]; !already {
				open[a.MonitorName] = &openIncident{start: a.SentAt}
			}
		case "up":
			if o, ok := open[a.MonitorName]; ok {
				incidents = append(incidents, Incident{
					MonitorName: a.MonitorName,
					StartedAt:   o.start,
					ResolvedAt:  a.SentAt,
				})
				delete(open, a.MonitorName)
			}
		}
	}

	// Remaining open entries are ongoing incidents.
	for name, o := range open {
		incidents = append(incidents, Incident{
			MonitorName: name,
			StartedAt:   o.start,
		})
	}

	// Sort newest-first.
	sort.Slice(incidents, func(i, j int) bool {
		return incidents[i].StartedAt.After(incidents[j].StartedAt)
	})

	if limit > 0 && len(incidents) > limit {
		incidents = incidents[:limit]
	}
	return incidents, nil
}

// --- helpers ---

func scanCheckRow(row *sql.Row) (*CheckRow, error) {
	var r CheckRow
	var ts int64
	var up int64
	err := row.Scan(&r.ID, &r.MonitorName, &ts, &up, &r.StatusCode, &r.ResponseMS, &r.Error)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	r.CheckedAt = time.Unix(ts, 0)
	r.Up = up != 0
	return &r, nil
}

func scanCheckRowFromRows(rows *sql.Rows) (*CheckRow, error) {
	var r CheckRow
	var ts int64
	var up int64
	if err := rows.Scan(&r.ID, &r.MonitorName, &ts, &up, &r.StatusCode, &r.ResponseMS, &r.Error); err != nil {
		return nil, err
	}
	r.CheckedAt = time.Unix(ts, 0)
	r.Up = up != 0
	return &r, nil
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
