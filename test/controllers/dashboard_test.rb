require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @monitor = monitors(:website)
    @monitor.checks.create!(up: true, status_code: 200, response_ms: 145, checked_at: 1.minute.ago)
    monitors(:ssh).checks.create!(up: false, error: "connection refused", checked_at: 1.minute.ago)
    monitors(:ssh).incidents.create!(started_at: 5.minutes.ago, reason: "connection refused")
  end

  test "the dashboard lists every monitor with its state" do
    get root_path

    assert_response :success
    assert_select "td a", text: "Main Website"
    assert_select ".status-badge--ok", text: "up"
    assert_select ".status-badge--crit", text: "down"
    assert_select ".cell-note", text: "connection refused"
  end

  test "history, incidents and monitor pages render" do
    get history_path
    assert_response :success
    assert_select "svg.sparkline", 2
    assert_select "circle.sparkline__down", 1

    get incidents_path
    assert_response :success
    assert_select ".status-badge", text: "ongoing"

    get monitor_path(@monitor)
    assert_response :success
    assert_select "td", text: "145 ms"
  end

  test "the public status page shows names and uptime but no targets or errors" do
    get status_path

    assert_response :success
    assert_select "h1", "Some systems are having problems"
    assert_select ".status-row__label", text: "SSH"
    assert_no_match "server1.example.test", response.body
    assert_no_match "connection refused", response.body
    assert_select "a[href=?]", alert_channels_path, count: 0
  end

  test "metrics are in the Prometheus text format" do
    get metrics_path

    assert_response :success
    assert_equal "text/plain; version=0.0.4; charset=utf-8", response.headers["Content-Type"]
    assert_includes response.body, "# TYPE arcline_uptime_up gauge\n"
    assert_includes response.body, %(arcline_uptime_up{monitor="Main Website"} 1\n)
    assert_includes response.body, %(arcline_uptime_up{monitor="SSH"} 0\n)
    assert_includes response.body, %(arcline_uptime_response_ms{monitor="Main Website"} 145\n)
    assert_includes response.body, %(arcline_uptime_uptime_24h{monitor="SSH"} 0.0000\n)
  end

  test "metric labels are escaped" do
    @monitor.update!(name: %(say "hi" \\ there))
    get metrics_path

    assert_includes response.body, %(arcline_uptime_up{monitor="say \\"hi\\" \\\\ there"} 1\n)
  end
end
