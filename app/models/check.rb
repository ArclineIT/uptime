class Check < ApplicationRecord
  belongs_to :monitor, class_name: "UptimeMonitor"

  scope :recent, -> { order(checked_at: :desc) }

  def self.prune(retention_days)
    return 0 unless retention_days.positive?

    where(checked_at: ...retention_days.days.ago).delete_all
  end
end
