# A recurring time range during which a monitor is not probed or alerted on.
class MaintenanceWindow < ApplicationRecord
  DAYS = %w[ mon tue wed thu fri sat sun ].freeze
  TIME = /\A([01]?\d|2[0-3]):[0-5]\d\z/

  belongs_to :monitor, class_name: "UptimeMonitor"

  normalizes :days, with: ->(days) { days.to_s.downcase.split(/[\s,]+/).compact_blank.join(",").presence || "*" }

  validates :starts_at, :ends_at, format: { with: TIME, message: "must be HH:MM" }
  validate :days_are_known

  def day_list
    days.split(",")
  end

  # Times are in the server's time zone. A start after the end crosses midnight.
  def active?(now = Time.current)
    return false unless day_list.include?("*") || day_list.include?(now.strftime("%a").downcase)

    minute = now.hour * 60 + now.min
    from, to = minutes(starts_at), minutes(ends_at)
    from <= to ? (from...to).cover?(minute) : minute >= from || minute < to
  end

  def to_s
    "#{days == '*' ? 'every day' : day_list.join(', ')} #{starts_at}–#{ends_at}"
  end

  private
    def minutes(clock)
      hour, minute = clock.split(":").map(&:to_i)
      hour * 60 + minute
    end

    def days_are_known
      unknown = day_list - DAYS - [ "*" ]
      errors.add(:days, "has unknown day #{unknown.to_sentence}") if unknown.any?
    end
end
