require "test_helper"

class NotifiersTest < ActiveSupport::TestCase
  include LocalServerHelper
  include ActionMailer::TestHelper

  test "discord and slack post JSON under their own key" do
    { "discord" => "content", "slack" => "text" }.each do |kind, key|
      with_http_server(http_response(204)) do |port, requests|
        AlertChannel.new(name: kind, kind: kind, url: "http://127.0.0.1:#{port}/hook").deliver("[DOWN] X", "body text")

        assert_match(/\APOST \/hook /, requests.first)
        assert_match %({"#{key}":"body text"}), requests.first
      end
    end
  end

  test "ntfy sends the subject as a title and the token as a bearer" do
    with_http_server(http_response(200)) do |port, requests|
      AlertChannel.new(name: "n", kind: "ntfy", url: "http://127.0.0.1:#{port}/topic", token: "tk").deliver("[DOWN] X", "body text")

      assert_match "Title: [DOWN] X", requests.first
      assert_match "Authorization: Bearer tk", requests.first
      assert requests.first.end_with?("body text")
    end
  end

  test "gotify posts to /message with the token and priority" do
    with_http_server(http_response(200)) do |port, requests|
      AlertChannel.new(name: "g", kind: "gotify", url: "http://127.0.0.1:#{port}/", token: "app", priority: 7).deliver("[DOWN] X", "body")

      assert_match(/\APOST \/message\?token=app /, requests.first)
      assert_match '"priority":7', requests.first
    end
  end

  test "a rejected or unreachable webhook raises Notifiers::Error" do
    with_http_server(http_response(500)) do |port|
      error = assert_raises(Notifiers::Error) { AlertChannel.new(kind: "discord", url: "http://127.0.0.1:#{port}/").deliver("s", "b") }
      assert_equal "discord returned 500", error.message
    end

    assert_raises(Notifiers::Error) { AlertChannel.new(kind: "discord", url: "http://127.0.0.1:#{closed_port}/").deliver("s", "b") }
  end

  test "email goes to every recipient as plain text" do
    assert_emails 1 do
      alert_channels(:email).deliver("[DOWN] X", "body text")
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal %w[ blake@example.test oncall@example.test ], mail.to
    assert_equal "[DOWN] X", mail.subject
    assert_equal "body text", mail.body.to_s
  end
end
