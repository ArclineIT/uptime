require "test_helper"

class AlertChannelsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "lists channels without exposing webhook paths or tokens" do
    get alert_channels_path

    assert_response :success
    assert_select "td", text: "discord.test"
    assert_no_match "webhooks/1/abc", response.body
  end

  test "creates each kind with its own requirements" do
    assert_difference -> { AlertChannel.count }, 2 do
      post alert_channels_path, params: { alert_channel: { name: "gotify-push", kind: "gotify", url: "https://gotify.example.test", token: "app", priority: 7 } }
      post alert_channels_path, params: { alert_channel: { name: "mail", kind: "email", recipients: "a@example.test" } }
    end

    assert_no_difference -> { AlertChannel.count } do
      post alert_channels_path, params: { alert_channel: { name: "bad-gotify", kind: "gotify", url: "https://gotify.example.test" } }
      post alert_channels_path, params: { alert_channel: { name: "bad-mail", kind: "email", recipients: " " } }
      post alert_channels_path, params: { alert_channel: { name: "bad-hook", kind: "slack", url: "not a url" } }
    end
    assert_response :unprocessable_entity
  end

  test "a blank token on update keeps the stored one" do
    channel = AlertChannel.create!(name: "ntfy", kind: "ntfy", url: "https://ntfy.example.test/topic", token: "keep-me")

    get edit_alert_channel_path(channel)
    assert_no_match "keep-me", response.body

    patch alert_channel_path(channel), params: { alert_channel: { name: "ntfy-renamed", token: "" } }
    assert_equal [ "ntfy-renamed", "keep-me" ], channel.reload.values_at(:name, :token)

    patch alert_channel_path(channel), params: { alert_channel: { token: "new-token" } }
    assert_equal "new-token", channel.reload.token
  end

  test "sends a test alert and reports a failure" do
    assert_emails 1 do
      post test_alert_channel_path(alert_channels(:email))
    end
    assert_equal "Test alert sent to email-blake.", flash[:notice]

    stub_method(Notifiers, :for, ->(_channel) { raise Notifiers::Error, "discord returned 404" }) do
      post test_alert_channel_path(alert_channels(:discord))
    end
    assert_equal "Test alert failed: discord returned 404", flash[:alert]
  end

  test "deletes a channel and its routes" do
    monitors(:website).alert_channels << alert_channels(:email)

    assert_difference -> { AlertChannel.count } => -1, -> { AlertRoute.count } => -1 do
      delete alert_channel_path(alert_channels(:email))
    end
  end
end
