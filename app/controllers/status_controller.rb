# Public status page: names and uptime only, no targets or error detail.
class StatusController < ApplicationController
  allow_public_access

  def show
    @statuses = MonitorStatus.all(UptimeMonitor.enabled.ordered)
    @all_up = @statuses.all? { |status| status.state != "down" }
  end
end
