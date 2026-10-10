require "test_helper"

class ProbesTest < ActiveSupport::TestCase
  include LocalServerHelper

  test "http is up on the expected status and records it" do
    with_http_server(http_response(200, "hello [arcline]")) do |port, requests|
      result = http(port, contains: "[arcline]", headers: { "X-Probe" => "yes" }).probe

      assert result.up, result.error
      assert_equal 200, result.status_code
      assert_equal "", result.error
      assert_match "User-Agent: arcline-uptime/1.0", requests.first
      assert_match "X-Probe: yes", requests.first
    end
  end

  test "http is down on an unexpected status" do
    with_http_server(http_response(503)) do |port|
      result = http(port).probe

      assert result.down?
      assert_equal 503, result.status_code
      assert_equal "expected status 200, got 503", result.error
    end
  end

  test "http is down when the body lacks the expected text" do
    with_http_server(http_response(200, "maintenance")) do |port|
      assert_equal 'body does not contain "[arcline]"', http(port, contains: "[arcline]").probe.error
    end
  end

  test "http follows redirects unless a redirect is the expected answer" do
    with_http_server(http_response(301, "", "Location" => "/next"), http_response(200, "ok")) do |port|
      assert http(port).probe.up
    end

    with_http_server(http_response(301, "", "Location" => "/next")) do |port|
      result = http(port, expected_status: 301).probe
      assert result.up
      assert_equal 301, result.status_code
    end
  end

  test "http sends the configured method and body" do
    with_http_server(http_response(200)) do |port, requests|
      http(port, http_method: "POST", body: '{"ping":true}').probe

      assert_match(/\APOST \/ HTTP/, requests.first)
      assert_match '{"ping":true}', requests.first
    end
  end

  test "http is down when the response is slower than the threshold" do
    with_http_server(-> { sleep 0.15; http_response(200) }) do |port|
      result = http(port, max_response_ms: 50).probe

      assert result.down?
      assert_match(/response time \d+ms exceeded threshold 50ms/, result.error)
    end
  end

  test "http is down, not raising, when nothing answers or it times out" do
    assert http(closed_port).probe.down?

    with_http_server(-> { sleep 1.5; http_response(200) }) do |port|
      result = http(port, timeout: 1).probe
      assert result.down?
      assert result.error.present?
    end
  end

  test "tcp is up when the port accepts and down when it refuses" do
    with_http_server do |port|
      assert UptimeMonitor.new(kind: "tcp", host: "127.0.0.1", port: port, timeout: 2).probe.up
    end

    result = UptimeMonitor.new(kind: "tcp", host: "127.0.0.1", port: closed_port, timeout: 2).probe
    assert result.down?
    assert_match(/refused/i, result.error)
  end

  test "tls is down when a certificate in the chain is inside the warning period" do
    Certificate = Struct.new(:not_after) unless self.class.const_defined?(:Certificate)
    monitor = UptimeMonitor.new(kind: "tls", host: "example.test", port: 443, timeout: 2, expiry_warning_days: 14)
    probe = Probes::Tls.new(monitor)

    stub_method(probe, :chain, [ Certificate.new(90.days.from_now), Certificate.new(10.days.from_now + 1.hour) ]) do
      result = probe.call
      assert result.down?
      assert_match(/\Acertificate expires in 10 day\(s\) on \d{4}-\d\d-\d\d\z/, result.error)
    end

    stub_method(probe, :chain, [ Certificate.new(90.days.from_now) ]) { assert probe.call.up }
    stub_method(probe, :chain, -> { raise OpenSSL::SSL::SSLError, "handshake failure" }) do
      assert_equal "handshake failure", probe.call.error
    end
  end

  test "dns checks that the name resolves and can require an address" do
    monitor = UptimeMonitor.new(kind: "dns", host: "example.test", timeout: 2)
    probe = Probes::Dns.new(monitor)

    stub_method(probe, :resolve, [ "203.0.113.10", "2001:db8::1" ]) do
      assert probe.call.up

      monitor.expected_ip = "2001:0db8:0000:0000:0000:0000:0000:0001"
      assert probe.call.up, "equal addresses in different spellings match"

      monitor.expected_ip = "203.0.113.99"
      assert_match 'expected IP "203.0.113.99" not found', probe.call.error
    end

    stub_method(probe, :resolve, []) { assert_equal "no addresses found for example.test", probe.call.error }
  end

  private
    def http(port, **attributes)
      UptimeMonitor.new(kind: "http", url: "http://127.0.0.1:#{port}/", timeout: 2, **attributes)
    end
end
