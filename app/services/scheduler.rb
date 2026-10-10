# Runs every due monitor, then sleeps briefly; the long-running half of the app
# (bin/rails uptime:run). Each tick probes due monitors on a few threads.
class Scheduler
  TICK = 1
  THREADS = 4

  def initialize(output: $stdout)
    @output = output
    @running = true
    @pruned_on = nil
  end

  def run
    trap("INT") { @running = false }
    trap("TERM") { @running = false }
    @output.puts "arcline-uptime scheduler started (#{UptimeMonitor.enabled.count} monitors)"

    while @running
      tick
      prune_daily
      sleep TICK
    end
    @output.puts "arcline-uptime scheduler stopped"
  end

  # Checks every monitor that is due. Returns the monitors it ran.
  def tick(now = Time.current)
    due = UptimeMonitor.enabled.includes(:maintenance_windows).select { |monitor| monitor.due?(now) }
    queue = Queue.new
    due.each { |monitor| queue << monitor }

    Array.new([ THREADS, due.size ].min) do
      Thread.new do
        while (monitor = queue.pop(true) rescue nil)
          ActiveRecord::Base.connection_pool.with_connection { check(monitor, now) }
        end
      end
    end.each(&:join)
    due
  end

  private
    def check(monitor, now)
      MonitorCheck.call(monitor, now: now)
    rescue StandardError => e
      Rails.logger.error("check crashed monitor=#{monitor.name.inspect}: #{e.class}: #{e.message}")
    end

    def prune_daily
      return if @pruned_on == Date.current

      @pruned_on = Date.current
      deleted = Check.prune(Rails.configuration.x.uptime.retention_days)
      Rails.logger.info("pruned #{deleted} old checks") if deleted.positive?
    end
end
