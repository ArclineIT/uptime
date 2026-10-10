# Prometheus text exposition.
class MetricsController < ApplicationController
  allow_public_access

  METRICS = [
    [ "up", "Whether the last check succeeded (1=up, 0=down)", ->(s) { s.up? ? 1 : 0 } ],
    [ "response_ms", "Response time of the last check in milliseconds", ->(s) { s.response_ms } ],
    [ "uptime_24h", "Uptime percentage over the last 24 hours", ->(s) { format("%.4f", s.uptime_24h) } ],
    [ "uptime_7d", "Uptime percentage over the last 7 days", ->(s) { format("%.4f", s.uptime_7d) } ]
  ].freeze

  def show
    statuses = MonitorStatus.all
    lines = METRICS.flat_map do |name, help, value|
      [ "# HELP arcline_uptime_#{name} #{help}", "# TYPE arcline_uptime_#{name} gauge" ] +
        statuses.map { |status| "arcline_uptime_#{name}{monitor=#{label(status.name)}} #{value.call(status)}" }
    end

    render plain: lines.join("\n") + "\n", content_type: "text/plain; version=0.0.4; charset=utf-8"
  end

  private
    def label(value)
      %("#{value.gsub('\\', '\\\\\\\\').gsub('"', '\"').gsub("\n", '\n')}")
    end
end
