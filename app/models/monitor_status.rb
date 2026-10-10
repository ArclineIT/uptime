# What the dashboard, status page and metrics show for one monitor.
MonitorStatus = Data.define(:monitor, :check, :uptime_24h, :uptime_7d, :uptime_30d) do
  def self.all(monitors = UptimeMonitor.ordered, now: Time.current)
    monitors.map do |monitor|
      new(monitor: monitor, check: monitor.latest_check,
          uptime_24h: monitor.uptime_percent(now - 24.hours),
          uptime_7d: monitor.uptime_percent(now - 7.days),
          uptime_30d: monitor.uptime_percent(now - 30.days))
    end
  end

  def name = monitor.name
  def up? = check&.up? || false
  def response_ms = check&.response_ms.to_i

  def state
    return "pending" if check.nil?

    up? ? "up" : "down"
  end
end
