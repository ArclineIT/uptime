# An endpoint that is probed on a schedule. Named UptimeMonitor because Ruby
# already has a Monitor class; the table is plain "monitors".
class UptimeMonitor < ApplicationRecord
  self.table_name = "monitors"

  KINDS = %w[ http tcp tls dns ].freeze
  HTTP_METHODS = %w[ GET HEAD POST PUT PATCH DELETE ].freeze

  has_many :checks, foreign_key: :monitor_id, dependent: :delete_all, inverse_of: :monitor
  has_many :incidents, foreign_key: :monitor_id, dependent: :delete_all, inverse_of: :monitor
  has_many :maintenance_windows, foreign_key: :monitor_id, dependent: :delete_all, inverse_of: :monitor
  has_many :alert_routes, foreign_key: :monitor_id, dependent: :delete_all, inverse_of: :monitor
  has_many :alert_channels, through: :alert_routes

  normalizes :name, :url, :host, :contains, :expected_ip, with: ->(value) { value.to_s.strip.presence }
  normalizes :http_method, with: ->(value) { value.to_s.strip.upcase.presence || "GET" }

  before_validation :apply_kind_defaults

  validates :name, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :http_method, inclusion: { in: HTTP_METHODS }
  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }, if: :http?
  validates :host, presence: true, unless: :http?
  validates :port, presence: true, numericality: { only_integer: true, in: 1..65_535 }, if: -> { tcp? || tls? }
  validates :expected_status, numericality: { only_integer: true, in: 100..599 }
  validates :interval, numericality: { only_integer: true, greater_than_or_equal_to: 5 }
  validates :timeout, numericality: { only_integer: true, in: 1..120 }
  validates :max_response_ms, :expiry_warning_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:name) }
  scope :enabled, -> { where(enabled: true) }

  KINDS.each do |kind|
    define_method(:"#{kind}?") { self.kind == kind }
  end

  def target
    http? ? url : [ host, port ].compact.join(":")
  end

  def due?(now = Time.current)
    enabled? && (last_checked_at.nil? || last_checked_at + interval <= now)
  end

  def in_maintenance?(now = Time.current)
    maintenance_windows.any? { |window| window.active?(now) }
  end

  def latest_check
    checks.order(checked_at: :desc).first
  end

  def open_incident
    incidents.where(resolved_at: nil).order(:started_at).last
  end

  # Percentage of checks since the given time that were up; 100 with no data.
  def uptime_percent(since)
    total = checks.where(checked_at: since..).count
    return 100.0 if total.zero?

    checks.where(checked_at: since.., up: true).count * 100.0 / total
  end

  # Alerts go to the routed channels, or to every channel when none are picked.
  def channels_to_alert
    alert_channels.any? ? alert_channels : AlertChannel.all
  end

  # Headers as the form edits them: one "Name: value" per line.
  def headers_text
    headers.map { |name, value| "#{name}: #{value}" }.join("\n")
  end

  def probe
    Probes.for(self).call
  end

  private
    def apply_kind_defaults
      self.port ||= 443 if tls?
    end
end
