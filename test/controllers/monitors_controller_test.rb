require "test_helper"

class MonitorsControllerTest < ActionDispatch::IntegrationTest
  test "creates an HTTP monitor with headers and routed channels" do
    assert_difference -> { UptimeMonitor.count } do
      post monitors_path, params: { uptime_monitor: {
        name: "API", kind: "http", url: "https://api.example.test/health", http_method: "post", expected_status: 200,
        headers_text: "Content-Type: application/json\nAuthorization: Bearer abc\nbroken line", body: '{"ping":true}',
        interval: 30, timeout: 5, max_response_ms: 0, enabled: "1", alert_channel_ids: [ alert_channels(:email).id ]
      } }
    end

    monitor = UptimeMonitor.find_by!(name: "API")
    assert_redirected_to monitor_path(monitor)
    assert_equal "POST", monitor.http_method
    assert_equal({ "Content-Type" => "application/json", "Authorization" => "Bearer abc" }, monitor.headers)
    assert_equal [ alert_channels(:email) ], monitor.alert_channels.to_a
  end

  test "shows validation errors" do
    assert_no_difference -> { UptimeMonitor.count } do
      post monitors_path, params: { uptime_monitor: { name: "", kind: "tcp", host: "example.test" } }
    end

    assert_response :unprocessable_entity
    assert_select ".form__errors li", text: "Name can't be blank"
    assert_select ".form__errors li", text: "Port can't be blank"
  end

  test "new and edit forms render" do
    get new_monitor_path
    assert_response :success

    get edit_monitor_path(monitors(:ssh))
    assert_response :success
    assert_select "input[name='uptime_monitor[host]'][value='server1.example.test']"
  end

  test "updates and deletes a monitor" do
    monitor = monitors(:ssh)

    patch monitor_path(monitor), params: { uptime_monitor: { port: 2222, enabled: "0" } }
    assert_redirected_to monitor_path(monitor)
    assert_equal [ 2222, false ], monitor.reload.values_at(:port, :enabled)

    assert_difference -> { UptimeMonitor.count }, -1 do
      delete monitor_path(monitor)
    end
  end

  test "check now runs a check and reports it" do
    monitor = monitors(:website)
    result = Probes::Result.new(up: false, status_code: 502, response_ms: 80, error: "expected status 200, got 502", checked_at: Time.current)
    AlertChannel.delete_all

    stub_method(Probes, :for, ->(_monitor) { Struct.new(:call).new(result) }) do
      assert_difference -> { monitor.checks.count } do
        post check_monitor_path(monitor)
      end
    end
    assert_equal "Down: expected status 200, got 502", flash[:notice]
  end

  test "adds and removes maintenance windows" do
    monitor = monitors(:website)

    assert_difference -> { monitor.maintenance_windows.count } do
      post monitor_maintenance_windows_path(monitor), params: { maintenance_window: { days: "sat,sun", starts_at: "02:00", ends_at: "06:00" } }
    end

    post monitor_maintenance_windows_path(monitor), params: { maintenance_window: { days: "*", starts_at: "nope", ends_at: "06:00" } }
    assert_match "must be HH:MM", flash[:alert]

    assert_difference -> { monitor.maintenance_windows.count }, -1 do
      delete monitor_maintenance_window_path(monitor, monitor.maintenance_windows.first)
    end
  end
end
