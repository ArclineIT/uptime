namespace :uptime do
  desc "Run the scheduler: checks every monitor on its interval until stopped"
  task run: :environment do
    $stdout.sync = true
    Scheduler.new.run
  end

  desc "Check one monitor by name, or all of them, once (no alerts, nothing stored)"
  task :check, [ :name ] => :environment do |_task, args|
    monitors = args[:name] ? UptimeMonitor.where(name: args[:name]) : UptimeMonitor.ordered
    abort "no monitor named #{args[:name].inspect}" if monitors.none?

    failed = monitors.count do |monitor|
      result = monitor.probe
      puts format("[%s] %-30s %5dms  %s", result.up ? " OK " : "DOWN", monitor.name, result.response_ms, result.error)
      result.down?
    end
    exit 1 if failed.positive?
  end

  desc "List configured monitors"
  task list: :environment do
    UptimeMonitor.ordered.each do |monitor|
      puts format("%-30s %-5s %-45s every %ds%s", monitor.name, monitor.kind, monitor.target, monitor.interval, monitor.enabled? ? "" : "  (disabled)")
    end
  end

  desc "Import monitors and alert channels from an arcline-uptime YAML config"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path] or abort "usage: bin/rails 'uptime:import[uptime.yaml]'"
    summary = ConfigImport.new(YAML.safe_load_file(path)).call
    puts "Imported #{summary[:monitors]} monitors and #{summary[:channels]} alert channels."
    summary[:notes].each { |note| puts "note: #{note}" }
  end

  desc "Delete check records older than UPTIME_RETENTION_DAYS"
  task prune: :environment do
    puts "Pruned #{Check.prune(Rails.configuration.x.uptime.retention_days)} checks."
  end
end
