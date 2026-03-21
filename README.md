# arcline-uptime

Lightweight uptime monitor for HTTP and TCP endpoints. Polls on a schedule, stores results in SQLite, sends alerts via Discord webhook or email. Includes an embedded web dashboard.

No external services required — runs as a single binary on any Linux server.

## Status

Planned. Not yet started.

## Stack

- Go — single static binary
- SQLite via `modernc.org/sqlite` (pure Go, no CGO)
- Config: YAML
- Alerts: Discord webhook, SMTP email

## Usage

```sh
arcline-uptime start --config uptime.yaml
arcline-uptime check --config uptime.yaml --monitor "Main Website"  # one-off check
```

Dashboard available at `http://localhost:8081` (configurable).

## Config

```yaml
global:
  check_interval: 60
  timeout: 10
  alert_cooldown: 300

alerts:
  - type: discord
    webhook_url: "https://discord.com/api/webhooks/..."

monitors:
  - name: "Main Website"
    type: http
    url: "https://arclineit.com"
    expected_status: 200
    contains: "[arcline]"

  - name: "SSH"
    type: tcp
    host: "server1.arclineit.com"
    port: 22
```

## Dashboard routes

- `/` — current status of all monitors
- `/history` — response time graph
- `/metrics` — Prometheus-compatible endpoint (optional)

Protected by basic auth configured in YAML.

See [todo.md](todo.md) for the full task list.
