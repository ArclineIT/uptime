class DashboardController < ApplicationController
  def show
    @statuses = MonitorStatus.all
  end
end
