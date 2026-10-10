class CreateUptimeTables < ActiveRecord::Migration[8.1]
  def change
    create_table :monitors do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.boolean :enabled, null: false, default: true

      # HTTP
      t.string :url
      t.string :http_method, null: false, default: "GET"
      t.text :body
      t.json :headers, null: false, default: {}
      t.integer :expected_status, null: false, default: 200
      t.string :contains

      # TCP / TLS / DNS
      t.string :host
      t.integer :port
      t.integer :expiry_warning_days, null: false, default: 14
      t.string :expected_ip

      t.integer :max_response_ms, null: false, default: 0
      t.integer :interval, null: false, default: 60
      t.integer :timeout, null: false, default: 10
      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :monitors, :name, unique: true

    create_table :checks do |t|
      t.references :monitor, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.boolean :up, null: false, default: false
      t.integer :status_code, null: false, default: 0
      t.integer :response_ms, null: false, default: 0
      t.string :error, null: false, default: ""
      t.datetime :checked_at, null: false
    end
    add_index :checks, [ :monitor_id, :checked_at ]
    add_index :checks, :checked_at

    create_table :incidents do |t|
      t.references :monitor, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :started_at, null: false
      t.datetime :resolved_at
      t.datetime :last_alerted_at
      t.string :reason, null: false, default: ""
    end
    add_index :incidents, :started_at

    create_table :alert_channels do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :url
      t.string :token
      t.integer :priority, null: false, default: 5
      t.text :recipients
      t.timestamps
    end
    add_index :alert_channels, :name, unique: true

    create_table :alert_routes do |t|
      t.references :monitor, null: false, foreign_key: { on_delete: :cascade }
      t.references :alert_channel, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :alert_routes, [ :monitor_id, :alert_channel_id ], unique: true

    create_table :maintenance_windows do |t|
      t.references :monitor, null: false, foreign_key: { on_delete: :cascade }
      t.string :days, null: false, default: "*"
      t.string :starts_at, null: false
      t.string :ends_at, null: false
      t.timestamps
    end
  end
end
