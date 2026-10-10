require "resolv"
require "openssl"
require "timeout"


# One probe class per monitor kind. Each returns a Probes::Result and never raises.
module Probes
  Result = Data.define(:up, :status_code, :response_ms, :error, :checked_at) do
    def down?
      !up
    end
  end

  def self.for(monitor)
    const_get(monitor.kind.capitalize).new(monitor)
  end

  class Base
    NETWORK_ERRORS = [ SystemCallError, SocketError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Resolv::ResolvError ].freeze

    def initialize(monitor)
      @monitor = monitor
    end

    def call
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @checked_at = Time.current
      @status_code = 0

      error = Timeout.timeout(@monitor.timeout) { check }
      error ||= threshold_error
      Result.new(up: error.nil?, status_code: @status_code, response_ms: elapsed_ms, error: error.to_s, checked_at: @checked_at)
    rescue *NETWORK_ERRORS => e
      Result.new(up: false, status_code: @status_code, response_ms: elapsed_ms, error: e.message, checked_at: @checked_at)
    end

    private
      # Subclasses return nil when the endpoint is healthy, or the failure message.
      def check
        raise NotImplementedError
      end

      def elapsed_ms
        @response_ms || ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started) * 1000).round
      end

      # Freezes the response time once the endpoint has answered.
      def mark_responded
        @response_ms = elapsed_ms
      end

      def threshold_error
        max = @monitor.max_response_ms
        "response time #{elapsed_ms}ms exceeded threshold #{max}ms" if max.positive? && elapsed_ms > max
      end
  end
end
