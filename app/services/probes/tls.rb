require "openssl"
require "socket"

module Probes
  # Fails when any certificate in the chain expires within the warning period.
  class Tls < Base
    private
      def check
        expires_at = chain.map(&:not_after).min
        mark_responded
        days_left = ((expires_at - Time.current) / 1.day).floor

        if days_left <= @monitor.expiry_warning_days
          "certificate expires in #{days_left} day(s) on #{expires_at.utc.to_date.iso8601}"
        end
      end

      def chain
        tcp = TCPSocket.new(@monitor.host, @monitor.port, connect_timeout: @monitor.timeout)
        context = OpenSSL::SSL::SSLContext.new
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)

        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.hostname = @monitor.host
        ssl.sync_close = true
        ssl.connect
        ssl.post_connection_check(@monitor.host)
        ssl.peer_cert_chain
      ensure
        ssl ? ssl.close : tcp&.close
      end
  end
end
