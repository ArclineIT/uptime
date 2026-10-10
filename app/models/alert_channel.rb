class AlertChannel < ApplicationRecord
  KINDS = %w[ discord slack email ntfy gotify ].freeze

  has_many :alert_routes, dependent: :delete_all
  has_many :monitors, through: :alert_routes

  normalizes :name, :url, :token, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }, unless: :email?
  validates :token, presence: true, if: -> { kind == "gotify" }
  validates :priority, numericality: { only_integer: true, in: 1..10 }
  validate :recipients_present, if: :email?

  scope :ordered, -> { order(:name) }

  def email?
    kind == "email"
  end

  def recipient_list
    recipients.to_s.split(/[\s,;]+/).compact_blank
  end

  def deliver(subject, body)
    Notifiers.for(self).deliver(subject, body)
  end

  private
    def recipients_present
      errors.add(:recipients, "must list at least one address") if recipient_list.empty?
    end
end
