require "test_helper"

class UptimeMonitorTest < ActiveSupport::TestCase
  test "each kind requires its own target" do
    assert_not UptimeMonitor.new(name: "a", kind: "http").valid?
    assert_not UptimeMonitor.new(name: "a", kind: "http", url: "ftp://example.test").valid?
    assert_not UptimeMonitor.new(name: "a", kind: "tcp", host: "example.test").valid?
    assert_not UptimeMonitor.new(name: "a", kind: "dns").valid?
    assert_not UptimeMonitor.new(name: "a", kind: "icmp", host: "example.test").valid?

    assert UptimeMonitor.new(name: "a", kind: "http", url: "https://example.test").valid?
    assert UptimeMonitor.new(name: "a", kind: "tcp", host: "example.test", port: 22).valid?
    assert UptimeMonitor.new(name: "a", kind: "dns", host: "example.test").valid?
  end

  test "tls defaults to port 443 and names are unique" do
    monitor = UptimeMonitor.new(name: "a", kind: "tls", host: "example.test")
    assert monitor.valid?
    assert_equal 443, monitor.port

    assert_not UptimeMonitor.new(name: "Main Website", kind: "dns", host: "example.test").valid?
  end

  test "due? follows the interval and the enabled flag" do
    monitor = monitors(:website)
    now = Time.current

    assert monitor.due?(now), "never checked"

    monitor.last_checked_at = now - 59.seconds
    assert_not monitor.due?(now)

    monitor.last_checked_at = now - 60.seconds
    assert monitor.due?(now)

    monitor.enabled = false
    assert_not monitor.due?(now)
  end

  test "uptime_percent is the share of successful checks, and 100 without data" do
    monitor = monitors(:website)
    assert_equal 100.0, monitor.uptime_percent(1.day.ago)

    [ true, true, true, false ].each_with_index { |up, i| monitor.checks.create!(up: up, checked_at: (i + 1).hours.ago) }
    monitor.checks.create!(up: false, checked_at: 3.days.ago)

    assert_in_delta 75.0, monitor.uptime_percent(1.day.ago)
    assert_in_delta 60.0, monitor.uptime_percent(7.days.ago)
  end

  test "alerts go to routed channels, or all of them when none are routed" do
    monitor = monitors(:website)
    assert_equal AlertChannel.count, monitor.channels_to_alert.count

    monitor.alert_channels << alert_channels(:email)
    assert_equal [ alert_channels(:email) ], monitor.channels_to_alert.to_a
  end

  test "deleting a monitor removes its history" do
    monitor = monitors(:website)
    monitor.checks.create!(up: true, checked_at: Time.current)
    monitor.incidents.create!(started_at: Time.current)

    assert_difference -> { Check.count } => -1, -> { Incident.count } => -1 do
      monitor.destroy
    end
  end
end
