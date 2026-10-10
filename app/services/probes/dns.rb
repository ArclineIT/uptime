require "resolv"
require "ipaddr"

module Probes
  # Resolves a hostname and can assert that a given address is among the answers.
  class Dns < Base
    private
      def check
        addresses = resolve(@monitor.host)
        mark_responded

        if addresses.empty?
          "no addresses found for #{@monitor.host}"
        elsif @monitor.expected_ip.present? && addresses.map { |a| normalize(a) }.exclude?(normalize(@monitor.expected_ip))
          "expected IP #{@monitor.expected_ip.inspect} not found in results #{addresses.inspect}"
        end
      end

      def resolve(host)
        Resolv.getaddresses(host)
      end

      # So different spellings of one address compare equal.
      def normalize(address)
        IPAddr.new(address).to_s
      rescue IPAddr::Error
        address
      end
  end
end
