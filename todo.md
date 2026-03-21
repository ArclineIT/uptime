# arcline-uptime — Lightweight Uptime Monitor

Polls HTTP/TCP endpoints on a schedule, stores results in SQLite, sends alerts
via webhook (Discord, Slack) and/or email. Single binary, no external services.

## Stack
- Language: Go
- Storage: SQLite (via modernc.org/sqlite — pure Go, no CGO)
- Config: YAML
- Alerts: HTTP webhook (Discord/Slack compatible), SMTP email
- Optional UI: embedded web dashboard (net/http + Go templates)

## Config format (uptime.yaml)
```yaml
global:
  check_interval: 60      # seconds
  timeout: 10             # seconds per check
  alert_cooldown: 300     # seconds between repeat alerts for same monitor

alerts:
  - type: discord
    webhook_url: "https://discord.com/api/webhooks/..."
  - type: email
    smtp_host: mail.arclineit.com
    smtp_port: 587
    from: alerts@arclineit.com
    to: blake@arclineit.com

monitors:
  - name: "Main Website"
    type: http
    url: "https://arclineit.com"
    expected_status: 200
    contains: "[arcline]"        # optional string check in body

  - name: "Control Panel"
    type: http
    url: "https://cp.arclineit.com"
    expected_status: 200

  - name: "SSH"
    type: tcp
    host: "server1.arclineit.com"
    port: 22

  - name: "Mail Server"
    type: tcp
    host: "mail.arclineit.com"
    port: 587
```

## Web dashboard
- `/` — current status of all monitors (live, auto-refresh)
- `/history` — response time graph (ASCII sparklines or simple SVG)
- `/metrics` — Prometheus-compatible text endpoint (optional)
- Protected by basic auth (config: dashboard.username / dashboard.password)

## Alert format (Discord example)
```
[DOWN] Main Website
Expected 200, got 503
Checked at 2026-03-03 14:32:01 UTC
Response time: 8043ms (timeout)
```

## Tasks
- [ ] Project scaffold
- [ ] YAML config parser
- [ ] HTTP monitor (status code, body contains, response time)
- [ ] TCP monitor (dial timeout)
- [ ] Scheduler (ticker per monitor, respect interval)
- [ ] SQLite schema (monitors, checks, alerts_sent)
- [ ] Result storage
- [ ] Discord webhook alerter
- [ ] SMTP email alerter
- [ ] Alert cooldown logic (don't spam on sustained outage)
- [ ] Recovery alert ("Main Website is back up, was down 12m 34s")
- [ ] Web dashboard — current status page
- [ ] Web dashboard — history / sparkline graph
- [ ] /metrics Prometheus endpoint
- [ ] Basic auth for dashboard
- [ ] systemd unit file example
- [ ] README with self-hosting guide
- [ ] Cross-compile Makefile
