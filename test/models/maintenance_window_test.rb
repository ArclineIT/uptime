require "test_helper"

class MaintenanceWindowTest < ActiveSupport::TestCase
  # 2026-06-06 is a Saturday.
  SATURDAY = Time.utc(2026, 6, 6)

  test "is active inside its hours on its days" do
    window = MaintenanceWindow.new(days: "sat,sun", starts_at: "02:00", ends_at: "06:00")

    assert window.active?(SATURDAY + 2.hours)
    assert window.active?(SATURDAY + 5.hours + 59.minutes)
    assert_not window.active?(SATURDAY + 6.hours)
    assert_not window.active?(SATURDAY + 1.hour)
    assert_not window.active?(SATURDAY - 1.day + 3.hours), "Friday is not listed"
  end

  test "a window can cross midnight" do
    window = MaintenanceWindow.new(days: "*", starts_at: "23:00", ends_at: "01:00")

    assert window.active?(SATURDAY + 23.hours + 30.minutes)
    assert window.active?(SATURDAY + 30.minutes)
    assert_not window.active?(SATURDAY + 12.hours)
  end

  test "blank days mean every day, and days are normalized" do
    assert_equal "*", MaintenanceWindow.new(days: " ").days
    assert_equal "mon,tue", MaintenanceWindow.new(days: "Mon, TUE").days
  end

  test "rejects unknown days and malformed times" do
    monitor = monitors(:website)

    assert_not monitor.maintenance_windows.new(days: "someday", starts_at: "02:00", ends_at: "03:00").valid?
    assert_not monitor.maintenance_windows.new(days: "*", starts_at: "25:00", ends_at: "03:00").valid?
    assert_not monitor.maintenance_windows.new(days: "*", starts_at: "2am", ends_at: "03:00").valid?
    assert monitor.maintenance_windows.new(days: "*", starts_at: "2:00", ends_at: "03:00").valid?
  end
end
