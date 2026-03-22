package web

import (
	"html/template"
	"time"
)

var funcMap = template.FuncMap{
	"fmtTime": func(t time.Time) string {
		if t.IsZero() {
			return "—"
		}
		return t.UTC().Format("2006-01-02 15:04:05")
	},
	"uptimeClass": func(pct float64) string {
		switch {
		case pct >= 99:
			return "good"
		case pct >= 95:
			return "warn"
		default:
			return "bad"
		}
	},
}

var (
	indexTmpl     = template.Must(template.New("index").Funcs(funcMap).Parse(indexHTML))
	historyTmpl   = template.Must(template.New("history").Funcs(funcMap).Parse(historyHTML))
	incidentsTmpl = template.Must(template.New("incidents").Funcs(funcMap).Parse(incidentsHTML))
	statusTmpl    = template.Must(template.New("status").Funcs(funcMap).Parse(statusHTML))
)

const sharedCSS = `
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Courier New', monospace; background: #0f0f0f; color: #d4d4d4; padding: 2rem; }
    h1 { color: #e2e2e2; margin-bottom: 0.25rem; font-size: 1.4rem; letter-spacing: 0.05em; }
    .subtitle { color: #666; font-size: 0.8rem; margin-bottom: 1.5rem; }
    nav { margin-bottom: 1.5rem; }
    nav a { color: #6b9edb; text-decoration: none; margin-right: 1.5rem; font-size: 0.85rem; }
    nav a:hover { color: #90bfff; }
    table { border-collapse: collapse; width: 100%; font-size: 0.875rem; }
    th { text-align: left; padding: 0.5rem 1rem; color: #888; font-weight: normal; border-bottom: 1px solid #2a2a2a; }
    td { padding: 0.5rem 1rem; border-bottom: 1px solid #1e1e1e; }
    tr:hover td { background: #161616; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 0.75rem; font-weight: bold; letter-spacing: 0.05em; }
    .badge-up   { background: #1a3a1a; color: #4caf50; border: 1px solid #2d5a2d; }
    .badge-down { background: #3a1a1a; color: #f44336; border: 1px solid #5a2d2d; }
    .good { color: #4caf50; }
    .warn { color: #ff9800; }
    .bad  { color: #f44336; }
    .dim  { color: #555; font-size: 0.8rem; }`

const sharedNav = `<nav>
    <a href="/">Dashboard</a>
    <a href="/history">History</a>
    <a href="/incidents">Incidents</a>
    <a href="/metrics">Metrics</a>
  </nav>`

const indexHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="30">
  <title>arcline-uptime</title>
  <style>` + sharedCSS + `</style>
</head>
<body>
  <h1>arcline-uptime</h1>
  <p class="subtitle">Auto-refreshes every 30s &mdash; {{fmtTime .Now}} UTC</p>
  ` + sharedNav + `
  <table>
    <thead>
      <tr>
        <th>Monitor</th>
        <th>Status</th>
        <th>Response</th>
        <th>24h</th>
        <th>7d</th>
        <th>30d</th>
        <th>Last Check</th>
        <th>Info</th>
      </tr>
    </thead>
    <tbody>
      {{range .Monitors}}
      <tr>
        <td>{{.Name}}</td>
        <td><span class="badge {{if .Up}}badge-up{{else}}badge-down{{end}}">{{if .Up}}UP{{else}}DOWN{{end}}</span></td>
        <td>{{if .ResponseMS}}{{.ResponseMS}}ms{{else}}<span class="dim">—</span>{{end}}</td>
        <td class="{{uptimeClass .Uptime24h}}">{{printf "%.2f" .Uptime24h}}%</td>
        <td class="{{uptimeClass .Uptime7d}}">{{printf "%.2f" .Uptime7d}}%</td>
        <td class="{{uptimeClass .Uptime30d}}">{{printf "%.2f" .Uptime30d}}%</td>
        <td class="dim">{{fmtTime .CheckedAt}}</td>
        <td class="dim">{{if .Error}}{{.Error}}{{else}}—{{end}}</td>
      </tr>
      {{end}}
    </tbody>
  </table>
</body>
</html>`

const historyHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>arcline-uptime — History</title>
  <style>` + sharedCSS + `
    h2 { color: #bbb; font-size: 1rem; margin: 2rem 0 0.5rem; font-weight: normal; }
    .sparkline-wrap { background: #161616; border: 1px solid #2a2a2a; border-radius: 4px; padding: 0.5rem; display: inline-block; }
    svg polyline { fill: none; stroke: #4caf5088; stroke-width: 1.5; }
    svg circle.down { fill: #f44336; }
    .stats { color: #666; font-size: 0.8rem; margin-top: 0.25rem; }
    .none { color: #444; font-style: italic; font-size: 0.875rem; }</style>
</head>
<body>
  ` + sharedNav + `
  <h1>Response Time History <span style="color:#555;font-size:0.8rem">(last 100 checks per monitor)</span></h1>
  {{range .}}
  <h2>{{.Name}}</h2>
  {{if .Points}}
  <div class="sparkline-wrap">
    <svg width="400" height="60" viewBox="0 0 400 60" xmlns="http://www.w3.org/2000/svg">
      <polyline points="{{.Points}}"/>
      {{range .DownDotXs}}
      <circle class="down" cx="{{.}}" cy="55" r="2.5"/>
      {{end}}
    </svg>
  </div>
  <p class="stats">max: {{.MaxMS}}ms &nbsp; avg: {{printf "%.0f" .AvgMS}}ms &nbsp; checks: {{.Count}}</p>
  {{else}}
  <p class="none">No data yet.</p>
  {{end}}
  {{end}}
</body>
</html>`

const incidentsHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>arcline-uptime — Incidents</title>
  <style>` + sharedCSS + `
    .ongoing { color: #f44336; font-weight: bold; }
    .resolved { color: #555; }</style>
</head>
<body>
  ` + sharedNav + `
  <h1>Incident Log</h1>
  <p class="subtitle" style="margin-bottom:1rem">All outage periods, newest first.</p>
  {{if .}}
  <table>
    <thead>
      <tr>
        <th>Monitor</th>
        <th>Started</th>
        <th>Resolved</th>
        <th>Duration</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      {{range .}}
      <tr>
        <td>{{.MonitorName}}</td>
        <td class="dim">{{fmtTime .StartedAt}}</td>
        <td class="dim">{{if .Ongoing}}—{{else}}{{fmtTime .ResolvedAt}}{{end}}</td>
        <td>{{.Duration}}</td>
        <td>{{if .Ongoing}}<span class="ongoing">ONGOING</span>{{else}}<span class="resolved">resolved</span>{{end}}</td>
      </tr>
      {{end}}
    </tbody>
  </table>
  {{else}}
  <p style="color:#555;margin-top:1rem">No incidents recorded.</p>
  {{end}}
</body>
</html>`

const statusHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>Service Status</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, sans-serif; background: #fafafa; color: #333; max-width: 700px; margin: 3rem auto; padding: 0 1rem; }
    h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
    .banner { padding: 1rem 1.5rem; border-radius: 6px; margin: 1.5rem 0; font-weight: 600; font-size: 1.1rem; }
    .banner-ok   { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
    .banner-down { background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th { text-align: left; padding: 0.5rem 0.75rem; color: #888; font-weight: 500; border-bottom: 1px solid #e5e7eb; font-size: 0.85rem; }
    td { padding: 0.6rem 0.75rem; border-bottom: 1px solid #f3f4f6; font-size: 0.9rem; }
    .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 6px; }
    .dot-up   { background: #22c55e; }
    .dot-down { background: #ef4444; }
    .uptime { color: #888; font-size: 0.85rem; }
    .footer { margin-top: 2rem; font-size: 0.75rem; color: #aaa; }
  </style>
</head>
<body>
  <h1>Service Status</h1>
  {{if .AllUp}}
  <div class="banner banner-ok">&#x2713; All systems operational</div>
  {{else}}
  <div class="banner banner-down">&#x26A0; Some services are experiencing issues</div>
  {{end}}
  <table>
    <thead>
      <tr><th>Service</th><th>Status</th><th>Uptime (24h)</th></tr>
    </thead>
    <tbody>
      {{range .Monitors}}
      <tr>
        <td>{{.Name}}</td>
        <td>
          <span class="dot {{if .Up}}dot-up{{else}}dot-down{{end}}"></span>
          {{if .Up}}Operational{{else}}Disrupted{{end}}
        </td>
        <td class="uptime">{{printf "%.2f" .Uptime24h}}%</td>
      </tr>
      {{end}}
    </tbody>
  </table>
  <p class="footer">Last updated: {{fmtTime .UpdatedAt}} UTC</p>
</body>
</html>`
