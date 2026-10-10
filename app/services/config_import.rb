# Loads the YAML config of the original Go arcline-uptime into the database.
# Running it again updates monitors and channels by name.
class ConfigImport
  def initialize(config)
    @config = config || {}
    @notes = []
  end

  def call
    ActiveRecord::Base.transaction do
      channels = Array(@config["alerts"]).each_with_index.map { |alert, index| import_channel(alert, index) }
      monitors = Array(@config["monitors"]).map { |monitor| import_monitor(monitor) }
      { channels: channels.size, monitors: monitors.size, notes: @notes }
    end
  end

  private
    def global
      @config["global"] || {}
    end

    def import_channel(alert, index)
      name = alert["name"].presence || "#{alert['type']}-#{index + 1}"
      channel = AlertChannel.find_or_initialize_by(name: name)
      channel.update!(
        kind: alert["type"],
        url: alert["webhook_url"].presence || alert["url"],
        token: alert["token"].presence,
        priority: alert["priority"].presence || 5,
        recipients: Array(alert["to"]).join(", ")
      )
      @notes << "#{name}: email is sent through this app's SMTP_* settings; smtp_host and credentials were not imported" if channel.email?
      channel
    end

    def import_monitor(config)
      monitor = UptimeMonitor.find_or_initialize_by(name: config["name"])
      monitor.assign_attributes(
        kind: config["type"],
        url: config["url"], http_method: config["method"].presence || "GET", body: config["body"],
        headers: config["headers"] || {}, expected_status: config["expected_status"].presence || 200,
        contains: config["contains"], host: config["host"], port: config["port"],
        expiry_warning_days: config["expiry_warning_days"].presence || 14, expected_ip: config["expected_ip"],
        max_response_ms: config["max_response_ms"].to_i,
        interval: config["interval"].presence || global["check_interval"].presence || 60,
        timeout: config["timeout"].presence || global["timeout"].presence || 10
      )
      monitor.save!

      monitor.alert_channels = Array(config["alert_names"]).map { |name| AlertChannel.find_by!(name: name) }
      monitor.maintenance_windows.destroy_all
      Array(config["maintenance"]).each do |window|
        monitor.maintenance_windows.create!(days: Array(window["days"]).join(","), starts_at: window["start"], ends_at: window["end"])
      end
      monitor
    end
end
