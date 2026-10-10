require "test_helper"

class ConfigImportTest < ActiveSupport::TestCase
  setup do
    [ AlertRoute, AlertChannel, UptimeMonitor ].each(&:delete_all)
    @config = YAML.safe_load_file(Rails.root.join("uptime.example.yaml"))
  end

  test "imports the example config" do
    summary = ConfigImport.new(@config).call

    assert_equal 8, summary[:monitors]
    assert_equal 4, summary[:channels]

    site = UptimeMonitor.find_by!(name: "Main Website")
    assert_equal [ "http", "https://arclineit.com", 3000 ], [ site.kind, site.url, site.max_response_ms ]
    assert_equal %w[ discord-ops email-blake ], site.alert_channels.map(&:name).sort

    api = UptimeMonitor.find_by!(name: "API Health Check")
    assert_equal "POST", api.http_method
    assert_equal "application/json", api.headers["Content-Type"]

    assert_equal [ 443, 21, 3600 ], UptimeMonitor.find_by!(name: "Main Website TLS").values_at(:port, :expiry_warning_days, :interval)
    assert_equal "sat,sun 02:00–06:00", UptimeMonitor.find_by!(name: "Backup Server SSH").maintenance_windows.first.to_s.sub(", ", ",")

    email = AlertChannel.find_by!(name: "email-blake")
    assert_equal %w[ blake@arclineit.com oncall@arclineit.com ], email.recipient_list
    assert_equal 7, AlertChannel.find_by!(name: "gotify-push").priority
  end

  test "importing twice updates in place" do
    ConfigImport.new(@config).call

    assert_no_difference [ -> { UptimeMonitor.count }, -> { AlertChannel.count }, -> { MaintenanceWindow.count } ] do
      ConfigImport.new(@config).call
    end
  end

  test "an unknown alert name rolls the whole import back" do
    @config["monitors"].first["alert_names"] = [ "nope" ]

    assert_raises(ActiveRecord::RecordNotFound) { ConfigImport.new(@config).call }
    assert_equal 0, UptimeMonitor.count
    assert_equal 0, AlertChannel.count
  end
end
