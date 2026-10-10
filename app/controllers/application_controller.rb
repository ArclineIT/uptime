class ApplicationController < ActionController::Base
  before_action :restrict_to_modern_browsers
  before_action :require_login

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  class << self
    # For the public status page and the Prometheus endpoint.
    def allow_public_access(**options)
      skip_before_action :require_login, **options
      skip_before_action :restrict_to_modern_browsers, **options
    end
  end

  private
    # HTTP basic auth from UPTIME_USERNAME and UPTIME_PASSWORD. With neither set
    # the dashboard is open, which is only allowed outside production.
    def require_login
      settings = Rails.configuration.x.uptime

      if settings.username && settings.password
        authenticate_or_request_with_http_basic("arcline-uptime") do |username, password|
          ActiveSupport::SecurityUtils.secure_compare(username, settings.username) &
            ActiveSupport::SecurityUtils.secure_compare(password, settings.password)
        end
      elsif Rails.env.production?
        render plain: "Set UPTIME_USERNAME and UPTIME_PASSWORD to use the dashboard.", status: :service_unavailable
      end
    end

    def restrict_to_modern_browsers
      allow_browser versions: :modern, block: :render_unsupported_browser
    end

    def render_unsupported_browser
      render file: Rails.root.join("public/406-unsupported-browser.html"), layout: false, status: :not_acceptable
    end
end
