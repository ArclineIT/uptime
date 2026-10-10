require "socket"

module Probes
  class Tcp < Base
    private
      def check
        TCPSocket.new(@monitor.host, @monitor.port, connect_timeout: @monitor.timeout).close
        mark_responded
        nil
      end
  end
end
