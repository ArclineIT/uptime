Rails.application.configure do
  # Seconds between repeat DOWN alerts while a monitor stays down.
  config.x.uptime.alert_cooldown = ENV.fetch("UPTIME_ALERT_COOLDOWN", 300).to_i
  # Delete check records older than this many days; 0 keeps them forever.
  config.x.uptime.retention_days = ENV.fetch("UPTIME_RETENTION_DAYS", 0).to_i
  # HTTP basic auth for the dashboard. The public status page and /metrics stay open.
  config.x.uptime.username = ENV["UPTIME_USERNAME"].presence
  config.x.uptime.password = ENV["UPTIME_PASSWORD"].presence
end
