# Decides what a finished check means for alerting: opens an incident and sends
# DOWN (repeating after the cooldown), or resolves it and sends a recovery.
class AlertPolicy
  def self.call(monitor, check)
    new(monitor, check).call
  end

  def initialize(monitor, check, cooldown: Rails.configuration.x.uptime.alert_cooldown)
    @monitor = monitor
    @check = check
    @cooldown = cooldown
  end

  def call
    @check.up? ? recover : alert_down
  end

  def self.down_message(monitor, check)
    subject = "[DOWN] #{monitor.name}"
    lines = [ subject ]
    lines << check.error if check.error.present?
    lines << "Status code: #{check.status_code}" unless check.status_code.zero?
    lines << "Checked at #{check.checked_at.utc.strftime('%Y-%m-%d %H:%M:%S')} UTC"
    lines << "Response time: #{check.response_ms}ms"
    [ subject, lines.join("\n") ]
  end

  def self.up_message(monitor, check, incident)
    subject = "[UP] #{monitor.name} is back up"
    lines = [
      subject,
      "Was down for #{format_duration(check.checked_at - incident.started_at)}",
      "Recovered at #{check.checked_at.utc.strftime('%Y-%m-%d %H:%M:%S')} UTC"
    ]
    [ subject, lines.join("\n") ]
  end

  # "1h 2m 3s", leaving out leading zero units.
  def self.format_duration(seconds)
    seconds = seconds.to_i
    hours, minutes, secs = seconds / 3600, seconds / 60 % 60, seconds % 60
    return "#{hours}h #{minutes}m #{secs}s" if hours.positive?

    minutes.positive? ? "#{minutes}m #{secs}s" : "#{secs}s"
  end

  private
    def alert_down
      incident = @monitor.open_incident ||
                 @monitor.incidents.create!(started_at: @check.checked_at, reason: @check.error)
      return unless incident.alert_due?(@cooldown, @check.checked_at)

      incident.update!(last_alerted_at: @check.checked_at)
      send_all(*self.class.down_message(@monitor, @check))
    end

    def recover
      incident = @monitor.open_incident or return

      incident.update!(resolved_at: @check.checked_at)
      send_all(*self.class.up_message(@monitor, @check, incident))
    end

    # One broken channel must not stop the others.
    def send_all(subject, body)
      @monitor.channels_to_alert.each do |channel|
        channel.deliver(subject, body)
      rescue Notifiers::Error => e
        Rails.logger.error("send alert failed monitor=#{@monitor.name.inspect} channel=#{channel.name.inspect}: #{e.message}")
      end
    end
end
