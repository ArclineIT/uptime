# One outage: opened by the first failed check, resolved by the next success.
class Incident < ApplicationRecord
  belongs_to :monitor, class_name: "UptimeMonitor"

  scope :recent, -> { order(started_at: :desc) }

  def ongoing?
    resolved_at.nil?
  end

  def duration(now = Time.current)
    (resolved_at || now) - started_at
  end

  def alert_due?(cooldown, now = Time.current)
    last_alerted_at.nil? || now - last_alerted_at >= cooldown
  end
end
