require "net/http"

module Probes
  class Http < Base
    MAX_REDIRECTS = 10
    MAX_BODY = 1.megabyte

    private
      def check
        response = fetch(URI.parse(@monitor.url), @monitor.http_method, @monitor.body.presence, MAX_REDIRECTS)
        mark_responded
        @status_code = response.code.to_i

        if @status_code != @monitor.expected_status
          "expected status #{@monitor.expected_status}, got #{@status_code}"
        elsif @monitor.contains.present? && !response.body.to_s.byteslice(0, MAX_BODY).include?(@monitor.contains)
          "body does not contain #{@monitor.contains.inspect}"
        end
      rescue URI::InvalidURIError => e
        "build request: #{e.message}"
      end

      def fetch(uri, method, body, redirects_left)
        request = Net::HTTPGenericRequest.new(method, body.present?, method != "HEAD", uri)
        request["User-Agent"] = "arcline-uptime/1.0"
        @monitor.headers.each { |name, value| request[name] = value }
        request.body = body if body.present?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = http.write_timeout = @monitor.timeout
        response = http.request(request)

        return response unless follow?(response)
        raise SocketError, "stopped after #{MAX_REDIRECTS} redirects" if redirects_left.zero?

        fetch(uri.merge(response["location"]), "GET", nil, redirects_left - 1)
      end

      # When a 3xx is the expected answer the redirect itself is the result.
      def follow?(response)
        response.is_a?(Net::HTTPRedirection) && response["location"].present? && !(300..399).cover?(@monitor.expected_status)
      end
  end
end
