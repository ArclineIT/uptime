# Probes one monitor, stores the result and runs the alert policy.
class MonitorCheck
  # Returns the saved Check, or nil when the monitor is in a maintenance window.
  def self.call(monitor, now: Time.current)
    return if monitor.in_maintenance?(now)

    result = monitor.probe
    check = monitor.checks.create!(result.to_h)
    monitor.update_columns(last_checked_at: result.checked_at)
    AlertPolicy.call(monitor, check)

    if check.up?
      Rails.logger.info("check ok monitor=#{monitor.name.inspect} ms=#{check.response_ms}")
    else
      Rails.logger.warn("check failed monitor=#{monitor.name.inspect} error=#{check.error.inspect}")
    end
    check
  end
end
