class AlertRoute < ApplicationRecord
  belongs_to :monitor, class_name: "UptimeMonitor"
  belongs_to :alert_channel
end
