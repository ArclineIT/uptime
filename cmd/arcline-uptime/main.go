package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"arclineit/arcline-uptime/internal/alert"
	"arclineit/arcline-uptime/internal/config"
	"arclineit/arcline-uptime/internal/monitor"
	"arclineit/arcline-uptime/internal/scheduler"
	"arclineit/arcline-uptime/internal/store"
	"arclineit/arcline-uptime/internal/web"
)

var version = "dev"

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "start":
		cmdStart(os.Args[2:])
	case "check":
		cmdCheck(os.Args[2:])
	case "list":
		cmdList(os.Args[2:])
	case "version":
		fmt.Println(version)
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, "arcline-uptime %s\n\nUsage:\n", version)
	fmt.Fprintf(os.Stderr, "  arcline-uptime start   [--config FILE] [--db FILE]\n")
	fmt.Fprintf(os.Stderr, "  arcline-uptime check   [--config FILE] [--monitor NAME]\n")
	fmt.Fprintf(os.Stderr, "  arcline-uptime list    [--config FILE]\n")
	fmt.Fprintf(os.Stderr, "  arcline-uptime version\n")
}

func cmdStart(args []string) {
	fs := flag.NewFlagSet("start", flag.ExitOnError)
	configPath := fs.String("config", "uptime.yaml", "path to config file")
	dbPath := fs.String("db", "uptime.db", "path to SQLite database")
	fs.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		os.Exit(1)
	}

	// Configure structured logging as early as possible.
	setupLogging(cfg.Global.LogFormat)

	db, err := store.Open(*dbPath)
	if err != nil {
		slog.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	checkers, err := monitor.BuildCheckers(cfg.Monitors, time.Duration(cfg.Global.Timeout)*time.Second)
	if err != nil {
		slog.Error("build monitors", "error", err)
		os.Exit(1)
	}

	alerters, err := alert.BuildNamedAlerters(cfg.Alerts)
	if err != nil {
		slog.Error("build alerters", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if cfg.Dashboard.Enabled {
		srv := web.NewServer(cfg, db)
		go func() {
			slog.Info("dashboard listening", "addr", cfg.Dashboard.Listen)
			if err := srv.ListenAndServe(); err != nil {
				slog.Error("dashboard server", "error", err)
			}
		}()
	}

	sched := scheduler.New(checkers, alerters, cfg.Monitors, db, cfg.Global)
	slog.Info("starting",
		"monitors", len(checkers),
		"interval", cfg.Global.CheckInterval,
		"retention_days", cfg.Global.RetentionDays,
	)
	sched.Start(ctx)

	<-ctx.Done()
	slog.Info("shutting down")
	sched.Wait()
}

func cmdCheck(args []string) {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	configPath := fs.String("config", "uptime.yaml", "path to config file")
	monitorName := fs.String("monitor", "", "monitor name (omit to check all)")
	fs.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		os.Exit(1)
	}

	checkers, err := monitor.BuildCheckers(cfg.Monitors, time.Duration(cfg.Global.Timeout)*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "monitors: %v\n", err)
		os.Exit(1)
	}

	exitCode := 0
	for _, c := range checkers {
		if *monitorName != "" && c.Name() != *monitorName {
			continue
		}
		r := c.Check()
		if r.Up {
			fmt.Printf("[OK]   %-30s  %dms\n", r.MonitorName, r.ResponseTime.Milliseconds())
		} else {
			fmt.Printf("[DOWN] %-30s  %s\n", r.MonitorName, r.Error)
			exitCode = 1
		}
	}
	os.Exit(exitCode)
}

func cmdList(args []string) {
	fs := flag.NewFlagSet("list", flag.ExitOnError)
	configPath := fs.String("config", "uptime.yaml", "path to config file")
	fs.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("%-30s %-6s %-10s %-40s\n", "NAME", "TYPE", "INTERVAL", "TARGET")
	fmt.Printf("%s %s %s %s\n",
		strings.Repeat("-", 30), strings.Repeat("-", 6),
		strings.Repeat("-", 10), strings.Repeat("-", 40))

	for _, m := range cfg.Monitors {
		target := m.URL
		if target == "" {
			target = fmt.Sprintf("%s:%d", m.Host, m.Port)
		}
		interval := fmt.Sprintf("%ds", m.Interval)
		fmt.Printf("%-30s %-6s %-10s %-40s\n", m.Name, m.Type, interval, target)
	}
}

func setupLogging(format string) {
	var h slog.Handler
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}
	if format == "json" {
		h = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		h = slog.NewTextHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(h))
}
