# Arcline Uptime

Lightweight uptime monitor for HTTP, TCP, TLS and DNS endpoints. It checks on a
schedule, stores results in SQLite, and alerts through Discord, Slack, email,
ntfy or Gotify. It includes a dashboard, a public status page and a Prometheus
endpoint.

This is the Ruby on Rails rewrite of the original Go service (preserved in the
repository history). Monitors and alert channels now live in the database and
are managed in the dashboard; an existing `uptime.yaml` can be imported.

## Features

- HTTP monitors: status code, optional body text, custom method, body and headers
- TCP monitors: connect within a timeout
- TLS monitors: alert before a certificate in the chain expires
- DNS monitors: the name resolves, optionally to an expected IP
- Slow-response threshold on every monitor
- Discord, Slack, email, ntfy and Gotify alert channels, with a "send test" button
- Per-monitor alert routing (no channels selected alerts all of them)
- Maintenance windows that pause checks and alerts
- Alert cooldown during a sustained outage, and a recovery alert with the downtime
- Dashboard with 24 hour, 7 day and 30 day uptime, response-time sparklines and an incident log
- Public status page and Prometheus `/metrics`

## Requirements

- Ruby 4.0+
- SQLite 3 (bundled via the `sqlite3` gem)

## Quick start

```bash
bin/setup --skip-server   # install gems and prepare the database
cp .env.example .env      # then fill in your values
bin/rails server          # dashboard on http://localhost:3000, or PORT if set
bin/rails uptime:run      # in a second terminal: the scheduler that runs the checks
```

The web server only shows results. Checks are made by the scheduler, so run
exactly one `bin/rails uptime:run` process alongside it.

## Importing an existing config

```bash
bin/rails 'uptime:import[uptime.yaml]'
```

This reads the YAML format of the Go version (see `uptime.example.yaml`) and
creates or updates monitors, alert channels, routing and maintenance windows by
name. Two things do not carry over:

- `dashboard.username` / `dashboard.password`: set `UPTIME_USERNAME` and
  `UPTIME_PASSWORD` instead.
- Per-channel SMTP settings: email alerts are sent through the app's `SMTP_*`
  settings. Recipients are imported.

`global.alert_cooldown` and `global.retention_days` become
`UPTIME_ALERT_COOLDOWN` and `UPTIME_RETENTION_DAYS`.

## Commands

| Command | What it does |
|---|---|
| `bin/rails uptime:run` | Run the scheduler until stopped |
| `bin/rails uptime:check` | Probe every monitor once and print the results; exits 1 if any is down |
| `bin/rails 'uptime:check[Main Website]'` | Probe one monitor by name |
| `bin/rails uptime:list` | List configured monitors |
| `bin/rails 'uptime:import[uptime.yaml]'` | Import a YAML config |
| `bin/rails uptime:prune` | Delete checks older than `UPTIME_RETENTION_DAYS` (the scheduler also does this daily) |

`uptime:check` only prints: it stores nothing and sends no alerts.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | HTTP listen port (the original service used `8081`) |
| `DATABASE_PATH` | `storage/<env>.sqlite3` | SQLite database file |
| `UPTIME_USERNAME` | — | Dashboard username (HTTP basic auth) |
| `UPTIME_PASSWORD` | — | Dashboard password |
| `UPTIME_ALERT_COOLDOWN` | `300` | Seconds between repeat DOWN alerts for one outage |
| `UPTIME_RETENTION_DAYS` | `0` | Delete checks older than this; `0` keeps them forever |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS` | — | SMTP server for email alert channels |
| `SMTP_FROM` | `alerts@arcline.it` | From address for email alerts |

In production the dashboard refuses to load until `UPTIME_USERNAME` and
`UPTIME_PASSWORD` are set. In development it is open when they are unset.

Webhook URLs and tokens for alert channels are stored in the database as
entered, so protect the SQLite file like the YAML config it replaces.

## Routes

| Route | Login | Description |
|---|---|---|
| `/` | yes | Monitors with current state and 24h / 7d / 30d uptime |
| `/monitors/:id` | yes | One monitor: recent checks, maintenance windows, check now |
| `/history` | yes | Response-time sparklines |
| `/incidents` | yes | Outages with start, end and duration |
| `/alert_channels` | yes | Alert channels |
| `/status` | no | Public status page: names and uptime only |
| `/metrics` | no | Prometheus text metrics |
| `/up` | no | Health check |

## Alert formats

```
[DOWN] Main Website
expected status 200, got 503
Status code: 503
Checked at 2026-03-21 14:32:01 UTC
Response time: 8043ms
```

```
[UP] Main Website is back up
Was down for 12m 34s
Recovered at 2026-03-21 14:44:35 UTC
```

## Prometheus metrics

```
arcline_uptime_up{monitor="Main Website"} 1
arcline_uptime_response_ms{monitor="Main Website"} 145
arcline_uptime_uptime_24h{monitor="Main Website"} 99.8600
arcline_uptime_uptime_7d{monitor="Main Website"} 99.9200
```

## Used by the portal

arcline-portal reads this app's database read-only (`UPTIME_DB_PATH` in the
portal) to show customers their service status. It depends on the `monitors`
table (`id`, `name`) and the `checks` table (`monitor_id`, `up`, `response_ms`,
`checked_at`), so keep those columns if the schema changes.

## Tests

```bash
bin/rails test
bin/rubocop
bin/brakeman
```

## Deployment

The app ships with a `Dockerfile` and a Kamal config (`config/deploy.yml`) with
two roles: `web` for the dashboard and `scheduler` for `bin/rails uptime:run`.
Both must share the `storage/` volume that holds the SQLite database.

## License

MIT. See [LICENSE](LICENSE).
