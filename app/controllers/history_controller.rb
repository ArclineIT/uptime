class HistoryController < ApplicationController
  POINTS = 100

  def show
    @sparklines = UptimeMonitor.ordered.map { |monitor| Sparkline.new(monitor, monitor.checks.recent.limit(POINTS).to_a) }
  end
end
