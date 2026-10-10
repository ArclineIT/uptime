require "test_helper"

class SchedulerTest < ActiveSupport::TestCase
  # The scheduler checks on its own threads, which cannot see a test transaction.
  self.use_transactional_tests = false

  setup do
    [ Check, Incident, AlertRoute, MaintenanceWindow, AlertChannel, UptimeMonitor ].each(&:delete_all)
    @due = UptimeMonitor.create!(name: "due", kind: "dns", host: "due.test")
    @fresh = UptimeMonitor.create!(name: "fresh", kind: "dns", host: "fresh.test", last_checked_at: Time.current)
    @off = UptimeMonitor.create!(name: "off", kind: "dns", host: "off.test", enabled: false)
  end

  teardown { [ Check, Incident, UptimeMonitor ].each(&:delete_all) }

  test "tick checks only the monitors that are due" do
    checked = Queue.new
    stub_method(MonitorCheck, :call, ->(monitor, **) { checked << monitor.name }) do
      ran = Scheduler.new(output: StringIO.new).tick

      assert_equal [ "due" ], ran.map(&:name)
      assert_equal [ "due" ], Array.new(checked.size) { checked.pop }
    end
  end

  test "tick stores real results from worker threads" do
    stub_method(Resolv, :getaddresses, [ "203.0.113.10" ]) do
      Scheduler.new(output: StringIO.new).tick
    end

    assert_equal 1, @due.checks.count
    assert @due.checks.first.up?
    assert_not_nil @due.reload.last_checked_at
  end

  test "a crashing check does not take the scheduler down" do
    stub_method(MonitorCheck, :call, ->(*, **) { raise "boom" }) do
      assert_nothing_raised { Scheduler.new(output: StringIO.new).tick }
    end
  end
end
