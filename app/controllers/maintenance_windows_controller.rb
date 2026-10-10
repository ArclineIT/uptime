class MaintenanceWindowsController < ApplicationController
  before_action :set_monitor

  def create
    window = @monitor.maintenance_windows.new(params.expect(maintenance_window: [ :days, :starts_at, :ends_at ]))
    flash[:alert] = window.errors.full_messages.to_sentence unless window.save
    redirect_to monitor_path(@monitor)
  end

  def destroy
    @monitor.maintenance_windows.find(params[:id]).destroy
    redirect_to monitor_path(@monitor), status: :see_other
  end

  private
    def set_monitor
      @monitor = UptimeMonitor.find(params[:monitor_id])
    end
end
