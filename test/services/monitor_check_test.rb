require "test_helper"

class MonitorCheckTest < ActiveSupport::TestCase
  setup { @monitor = monitors(:website) }

  test "stores the result and stamps the monitor" do
    at = Time.utc(2026, 6, 1, 12)
    result = Probes::Result.new(up: true, status_code: 200, response_ms: 145, error: "", checked_at: at)

    stub_method(@monitor, :probe, result) do
      check = MonitorCheck.call(@monitor)

      assert check.up?
      assert_equal 145, check.response_ms
      assert_equal at, @monitor.reload.last_checked_at
    end
  end

  test "a failure opens an incident" do
    result = Probes::Result.new(up: false, status_code: 0, response_ms: 10, error: "connection refused", checked_at: Time.current)
    AlertChannel.delete_all

    stub_method(@monitor, :probe, result) do
      assert_difference -> { Incident.count } do
        MonitorCheck.call(@monitor)
      end
    end
    assert_equal "connection refused", @monitor.open_incident.reason
  end

  test "nothing is probed during a maintenance window" do
    @monitor.maintenance_windows.create!(days: "*", starts_at: "00:00", ends_at: "23:59")

    stub_method(@monitor, :probe, -> { flunk "should not probe" }) do
      assert_no_difference -> { Check.count } do
        assert_nil MonitorCheck.call(@monitor, now: Time.current.change(hour: 12))
      end
    end
  end
end
