require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @settings = Rails.configuration.x.uptime
    @settings.username, @settings.password = "admin", "s3cret-pass"
  end

  teardown { @settings.username = @settings.password = nil }

  test "the dashboard asks for the configured credentials" do
    get root_path
    assert_response :unauthorized

    get root_path, headers: basic("admin", "wrong")
    assert_response :unauthorized

    get root_path, headers: basic("admin", "s3cret-pass")
    assert_response :success
  end

  test "changes need credentials too" do
    assert_no_difference -> { UptimeMonitor.count } do
      delete monitor_path(monitors(:website))
      post monitors_path, params: { uptime_monitor: { name: "x", kind: "dns", host: "x.test" } }
    end
    assert_response :unauthorized
  end

  test "the status page, metrics and health check stay public" do
    [ status_path, metrics_path, rails_health_check_path ].each do |path|
      get path
      assert_response :success, path
    end
  end

  private
    def basic(username, password)
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
    end
end
