require "test_helper"

class AlertPolicyTest < ActiveSupport::TestCase
  setup do
    @monitor = monitors(:website)
    @sent = []
    sent = @sent
    @original = Notifiers.method(:for)
    Notifiers.define_singleton_method(:for) do |channel|
      Object.new.tap { |n| n.define_singleton_method(:deliver) { |subject, body| sent << [ channel.name, subject, body ] } }
    end
  end

  teardown { Notifiers.define_singleton_method(:for, @original) }

  test "the first failure opens an incident and alerts every channel" do
    check = record(up: false, error: "expected status 200, got 503", status_code: 503, response_ms: 8043, at: Time.utc(2026, 3, 21, 14, 32, 1))

    assert_difference -> { @monitor.incidents.count } do
      AlertPolicy.call(@monitor, check)
    end

    assert_equal %w[ discord-ops email-blake ], @sent.map(&:first).sort
    assert_equal "[DOWN] Main Website", @sent.first[1]
    assert_equal <<~BODY.strip, @sent.first[2]
      [DOWN] Main Website
      expected status 200, got 503
      Status code: 503
      Checked at 2026-03-21 14:32:01 UTC
      Response time: 8043ms
    BODY
  end

  test "a sustained outage alerts again only after the cooldown" do
    start = Time.utc(2026, 3, 21, 14, 0, 0)
    policy = ->(at) { AlertPolicy.new(@monitor, record(up: false, at: at), cooldown: 300).call }

    policy.call(start)
    policy.call(start + 60)
    policy.call(start + 299)
    assert_equal 2, @sent.size, "one alert per channel"

    policy.call(start + 300)
    assert_equal 4, @sent.size
    assert_equal 1, @monitor.incidents.count
  end

  test "recovery resolves the incident and reports how long it was down" do
    start = Time.utc(2026, 3, 21, 14, 32, 1)
    AlertPolicy.call(@monitor, record(up: false, at: start))
    @sent.clear

    AlertPolicy.call(@monitor, record(up: true, at: start + 12.minutes + 34.seconds))

    assert_nil @monitor.open_incident
    assert_equal "[UP] Main Website is back up", @sent.first[1]
    assert_equal "[UP] Main Website is back up\nWas down for 12m 34s\nRecovered at 2026-03-21 14:44:35 UTC", @sent.first[2]
  end

  test "a healthy check with no open incident sends nothing" do
    AlertPolicy.call(@monitor, record(up: true))
    assert_empty @sent
    assert_equal 0, @monitor.incidents.count
  end

  test "only routed channels are alerted" do
    @monitor.alert_channels << alert_channels(:email)
    AlertPolicy.call(@monitor, record(up: false))

    assert_equal [ "email-blake" ], @sent.map(&:first)
  end

  test "a failing channel does not stop the others" do
    sent = @sent
    Notifiers.define_singleton_method(:for) do |channel|
      Object.new.tap do |n|
        n.define_singleton_method(:deliver) do |subject, _body|
          raise Notifiers::Error, "boom" if channel.name == "discord-ops"
          sent << [ channel.name, subject ]
        end
      end
    end

    AlertPolicy.call(@monitor, record(up: false))
    assert_equal [ "email-blake" ], @sent.map(&:first)
  end

  test "format_duration drops leading zero units" do
    assert_equal "45s", AlertPolicy.format_duration(45)
    assert_equal "12m 34s", AlertPolicy.format_duration(754)
    assert_equal "2h 0m 5s", AlertPolicy.format_duration(7205)
  end

  private
    def record(up:, at: Time.current, **attributes)
      @monitor.checks.create!(up: up, checked_at: at, **attributes)
    end
end
