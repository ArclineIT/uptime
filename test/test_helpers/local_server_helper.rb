require "socket"

# Tiny local servers so probes can be tested without leaving the machine.
module LocalServerHelper
  # Serves the given raw HTTP responses, one per connection, and yields the port.
  # Requests are collected in the returned array.
  def with_http_server(*responses)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      responses.each do |response|
        client = server.accept
        request = +""
        while (line = client.gets) && line != "\r\n"
          request << line
        end
        length = request[/content-length: (\d+)/i, 1].to_i
        request << client.read(length) if length.positive?
        requests << request
        response = response.call if response.respond_to?(:call)
        client.write(response)
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end

    yield server.addr[1], requests
  ensure
    server&.close
    thread&.join(2)
  end

  def http_response(status, body = "", headers = {})
    head = { "Content-Length" => body.bytesize, "Connection" => "close" }.merge(headers)
    "HTTP/1.1 #{status} X\r\n#{head.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n#{body}"
  end

  # A port that nothing is listening on.
  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end
end
