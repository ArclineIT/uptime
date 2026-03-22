# arcline-uptime — Lightweight Uptime Monitor

Polls HTTP/TCP/TLS/DNS endpoints on a schedule, stores results in SQLite, sends alerts
via webhook (Discord, Slack), email, ntfy, or Gotify. Single binary, no external services.

## Stack
- Language: Go
- Storage: SQLite (via modernc.org/sqlite — pure Go, no CGO)
- Config: YAML
- Alerts: Discord/Slack webhook, SMTP email, ntfy.sh, Gotify
- UI: embedded web dashboard (net/http + Go templates)

## Done
- [x] Project scaffold
- [x] YAML config parser
- [x] HTTP monitor (status code, body contains, response time threshold)
- [x] HTTP POST/PUT with custom body and headers
- [x] TCP monitor (dial timeout)
- [x] TLS certificate expiry monitor
- [x] DNS resolution monitor (optional expected IP assertion)
- [x] Per-monitor interval and timeout overrides
- [x] Scheduler (ticker per monitor, immediate first check)
- [x] SQLite schema (checks, alerts_sent)
- [x] Result storage with configurable retention / auto-pruning
- [x] Discord / Slack webhook alerter
- [x] SMTP email alerter (multiple recipients)
- [x] ntfy.sh alerter
- [x] Gotify alerter
- [x] Per-monitor alert routing (named alerters)
- [x] Maintenance windows (suppress alerts on a schedule)
- [x] Alert cooldown logic (don't spam on sustained outage)
- [x] Recovery alert ("Main Website is back up, was down 12m 34s")
- [x] Web dashboard — current status page (24h / 7d / 30d uptime)
- [x] Web dashboard — history / SVG sparkline graph with down markers
- [x] Web dashboard — incident log
- [x] Public status page (no auth)
- [x] /metrics Prometheus endpoint (up, response_ms, uptime_24h, uptime_7d)
- [x] Basic auth for dashboard
- [x] systemd unit file example
- [x] README with self-hosting guide
- [x] Cross-compile Makefile
- [x] Structured logging (slog, text or JSON)
- [x] `start`, `check`, `list`, `version` CLI subcommands

## Ideas
- [ ] ICMP/ping monitor
- [ ] HTTP response header assertion
- [ ] HTTP JSON path check
- [ ] SSH command check
- [ ] Generic webhook alerter (configurable template body)
- [ ] Telegram alerter
- [ ] PagerDuty alerter
- [ ] Escalation policy (alert A immediately, alert B after N minutes still down)
- [ ] `test-alert` subcommand
- [ ] `validate` subcommand (parse config, print summary, exit non-zero on errors)
- [ ] `--dry-run` flag for start (run checks, no alerts)
- [ ] Per-monitor detail page with full history and time-axis chart
- [ ] Uptime calendar heatmap (GitHub-style, per day)
- [ ] CSV / JSON export of check history
- [ ] JSON API (/api/v1/monitors, /api/v1/monitors/{name}/checks)
- [ ] Environment variable substitution in config (${VAR})
- [ ] Config hot-reload on SIGHUP
- [ ] TLS for the dashboard itself
- [ ] Database backup command
