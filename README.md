# arcline-uptime

Lightweight uptime monitor for HTTP and TCP endpoints. Polls on a schedule, stores results in SQLite, sends alerts via Discord, Slack, email, ntfy, or Gotify. Includes an embedded web dashboard.

**No external services required** — runs as a single binary on any Linux server.

## Features

- HTTP monitors — status code, optional body string check, response time threshold
- HTTP POST/PUT with custom body and headers
- TCP monitors — dial timeout
- TLS certificate expiry alerts
- DNS resolution checks with optional expected IP assertion
- Discord / Slack webhook alerts
- SMTP email alerts (multiple recipients, STARTTLS)
- ntfy.sh push notifications
- Gotify push notifications
- Per-monitor alert routing
- Maintenance windows (suppress alerts during scheduled downtime)
- Alert cooldown (no spam on sustained outages)
- Recovery alerts ("Main Website is back up, was down 12m 34s")
- Embedded web dashboard with history sparklines and incident log
- Public status page (no auth)
- Prometheus `/metrics` endpoint
- SQLite storage with configurable retention
- Single static binary — no CGO, cross-compiles easily

---

## Quick start

```sh
# Build
make build

# Create your config
cp uptime.example.yaml uptime.yaml
$EDITOR uptime.yaml

# Run
./arcline-uptime start --config uptime.yaml

# One-off check without starting the daemon
./arcline-uptime check --config uptime.yaml --monitor "Main Website"

# List configured monitors
./arcline-uptime list --config uptime.yaml
```

Dashboard available at `http://localhost:8081` (configure `dashboard.listen`).

---

## Installation (Linux server)

### 1. Build or download the binary

```sh
# Build for the current system
make build

# Cross-compile for Linux amd64
make linux-amd64

# Cross-compile for Linux arm64
make linux-arm64
```

### 2. Install

```sh
# Create a dedicated user
useradd -r -s /usr/sbin/nologin -d /opt/arcline-uptime arcline

# Copy binary and config
mkdir -p /opt/arcline-uptime
install -m 0755 arcline-uptime /opt/arcline-uptime/arcline-uptime
cp uptime.example.yaml /opt/arcline-uptime/uptime.yaml
chown -R arcline:arcline /opt/arcline-uptime

# Edit your config
$EDITOR /opt/arcline-uptime/uptime.yaml
```

### 3. Configure systemd

```sh
cp arcline-uptime.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now arcline-uptime
systemctl status arcline-uptime
journalctl -u arcline-uptime -f
```

---

## Configuration reference

### `global`

| Key | Default | Description |
|-----|---------|-------------|
| `check_interval` | `60` | Seconds between checks (can be overridden per monitor) |
| `timeout` | `10` | Seconds per probe (can be overridden per monitor) |
| `alert_cooldown` | `300` | Seconds between repeat DOWN alerts for the same monitor |
| `retention_days` | `0` | Delete check records older than this; `0` keeps forever |
| `log_format` | `text` | `text` for human-readable, `json` for structured output |

### `alerts`

Each entry in the `alerts` list defines one notification channel.

| Key | Required for | Description |
|-----|-------------|-------------|
| `name` | — | Optional name for per-monitor routing |
| `type` | all | `discord`, `slack`, `email`, `ntfy`, `gotify` |
| `webhook_url` | discord/slack | Full webhook URL |
| `smtp_host` | email | SMTP server hostname |
| `smtp_port` | email | SMTP port (587 for STARTTLS) |
| `from` | email | Sender address |
| `to` | email | Recipient(s); accepts a single string or a list |
| `username` | email | SMTP auth username |
| `password` | email | SMTP auth password |
| `url` | ntfy/gotify | ntfy topic URL or Gotify server base URL |
| `token` | ntfy/gotify | Bearer token (ntfy) or app token (Gotify) |
| `priority` | gotify | Notification priority 1–10; default `5` |

### `monitors`

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | ✓ | Unique display name |
| `type` | string | ✓ | `http`, `tcp`, `tls`, `dns` |
| `url` | string | http | Full URL to probe |
| `method` | string | — | HTTP method; default `GET` |
| `body` | string | — | HTTP request body |
| `headers` | map | — | Additional HTTP request headers |
| `expected_status` | int | — | Expected HTTP status code; default `200` |
| `contains` | string | — | Assert response body contains this string |
| `host` | string | tcp/tls/dns | Hostname |
| `port` | int | tcp/tls | Port number |
| `expiry_warning_days` | int | — | Alert when TLS cert expires within N days; default `14` |
| `expected_ip` | string | — | DNS: assert this IP is in the results |
| `max_response_ms` | int | — | Alert if response time exceeds this; `0` disables |
| `interval` | int | — | Override global `check_interval` for this monitor |
| `timeout` | int | — | Override global `timeout` for this monitor |
| `alert_names` | list | — | Route alerts only to these named alerters; empty = all |
| `maintenance` | list | — | Suppress alerts during these time windows |

#### Maintenance windows

```yaml
maintenance:
  - days: [mon, tue, wed, thu, fri]   # weekday names (3-letter), or "*" for all
    start: "23:00"                     # HH:MM in server local time
    end: "01:00"                       # supports overnight ranges
```

### `dashboard`

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | `false` | Start the web dashboard |
| `listen` | `:8081` | Address to listen on |
| `username` | — | Basic auth username; leave empty to disable auth |
| `password` | — | Basic auth password |

---

## Dashboard routes

| Route | Auth | Description |
|-------|------|-------------|
| `/` | ✓ | Current status table with 24h/7d/30d uptime |
| `/history` | ✓ | Response time sparklines per monitor |
| `/incidents` | ✓ | Incident log — all outage periods with duration |
| `/metrics` | — | Prometheus-compatible text metrics |
| `/status` | — | Public status page (no sensitive details) |

---

## Alert formats

**DOWN alert:**
```
[DOWN] Main Website
expected status 200, got 503
Checked at 2026-03-21 14:32:01 UTC
Response time: 8043ms
```

**Recovery alert:**
```
[UP] Main Website is back up
Was down for 12m 34s
Recovered at 2026-03-21 14:44:35 UTC
```

---

## Prometheus metrics

```
# HELP arcline_uptime_up Whether the last check succeeded (1=up, 0=down)
arcline_uptime_up{monitor="Main Website"} 1
arcline_uptime_up{monitor="SSH"} 0

# HELP arcline_uptime_response_ms Response time of the last check in milliseconds
arcline_uptime_response_ms{monitor="Main Website"} 145

# HELP arcline_uptime_uptime_24h Uptime percentage over the last 24 hours
arcline_uptime_uptime_24h{monitor="Main Website"} 99.8600

# HELP arcline_uptime_uptime_7d Uptime percentage over the last 7 days
arcline_uptime_uptime_7d{monitor="Main Website"} 99.9200
```

---

## Building

```sh
make build          # binary in current directory
make linux-amd64    # arcline-uptime-linux-amd64
make linux-arm64    # arcline-uptime-linux-arm64
make all            # both cross-compile targets
make test           # run tests
make clean          # remove binaries
```

No CGO is required. Cross-compilation works without a C toolchain.

---

## License

MIT — see [LICENSE](LICENSE).
