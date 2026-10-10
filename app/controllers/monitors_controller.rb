class MonitorsController < ApplicationController
  before_action :set_monitor, only: %i[ show edit update destroy check ]

  def show
    @checks = @monitor.checks.recent.limit(50)
    @window = @monitor.maintenance_windows.new
  end

  def new
    @monitor = UptimeMonitor.new(kind: "http")
  end

  def create
    @monitor = UptimeMonitor.new(monitor_params)

    if @monitor.save
      redirect_to monitor_path(@monitor), notice: "#{@monitor.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @monitor.update(monitor_params)
      redirect_to monitor_path(@monitor), notice: "#{@monitor.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @monitor.destroy
    redirect_to root_path, notice: "#{@monitor.name} deleted.", status: :see_other
  end

  # Runs one check right now, outside the schedule.
  def check
    check = MonitorCheck.call(@monitor)
    message = if check.nil? then "In a maintenance window; not checked."
    elsif check.up? then "Up in #{check.response_ms}ms."
    else "Down: #{check.error}"
    end
    redirect_to monitor_path(@monitor), notice: message
  end

  private
    def set_monitor
      @monitor = UptimeMonitor.find(params[:id])
    end

    def monitor_params
      permitted = params.expect(uptime_monitor: [
        :name, :kind, :enabled, :url, :http_method, :body, :expected_status, :contains, :host, :port,
        :expiry_warning_days, :expected_ip, :max_response_ms, :interval, :timeout, :headers_text, alert_channel_ids: []
      ])
      permitted[:headers] = parse_headers(permitted.delete(:headers_text))
      permitted
    end

    # One "Name: value" per line.
    def parse_headers(text)
      text.to_s.lines.filter_map do |line|
        name, value = line.split(":", 2).map { |part| part.to_s.strip }
        [ name, value ] if name.present? && value.present?
      end.to_h
    end
end
