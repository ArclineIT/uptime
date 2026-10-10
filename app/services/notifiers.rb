require "net/http"

# Delivers an alert to one channel. Each notifier raises Notifiers::Error on failure.
module Notifiers
  Error = Class.new(StandardError)
  TIMEOUT = 10

  def self.for(channel)
    case channel.kind
    when "discord" then Webhook.new(channel, key: "content")
    when "slack" then Webhook.new(channel, key: "text")
    when "ntfy" then Ntfy.new(channel)
    when "gotify" then Gotify.new(channel)
    when "email" then Email.new(channel)
    else raise Error, "unknown channel kind #{channel.kind.inspect}"
    end
  end

  class Base
    def initialize(channel)
      @channel = channel
    end

    private
      def post(url, body, headers = {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = TIMEOUT

        response = http.post(uri.request_uri, body, headers)
        raise Error, "#{@channel.kind} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      rescue SystemCallError, SocketError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
        raise Error, "post #{@channel.kind}: #{e.message}"
      end
  end

  # Discord and Slack incoming webhooks differ only in the name of the text field.
  class Webhook < Base
    def initialize(channel, key:)
      super(channel)
      @key = key
    end

    def deliver(_subject, body)
      post(@channel.url, { @key => body }.to_json, "Content-Type" => "application/json")
    end
  end

  # The URL is the full topic URL, e.g. https://ntfy.sh/my-topic.
  class Ntfy < Base
    def deliver(subject, body)
      headers = { "Content-Type" => "text/plain", "Title" => subject }
      headers["Authorization"] = "Bearer #{@channel.token}" if @channel.token.present?
      post(@channel.url, body, headers)
    end
  end

  class Gotify < Base
    def deliver(subject, body)
      url = "#{@channel.url.chomp('/')}/message?token=#{CGI.escape(@channel.token.to_s)}"
      post(url, { title: subject, message: body, priority: @channel.priority }.to_json, "Content-Type" => "application/json")
    end
  end

  class Email < Base
    def deliver(subject, body)
      AlertMailer.alert(@channel.recipient_list, subject, body).deliver_now
    rescue StandardError => e
      raise Error, "send email: #{e.message}"
    end
  end
end
