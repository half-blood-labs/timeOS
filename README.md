# TimeOS

[![Hex.pm](https://img.shields.io/hexpm/v/timeos.svg)](https://hex.pm/packages/timeos)
[![CI](https://github.com/ijunaid8989/timeOS/workflows/CI/badge.svg)](https://github.com/ijunaid8989/timeOS/actions)

**TimeOS** is a production-ready temporal rule engine for Elixir that enables you to schedule jobs based on events, time intervals, and cron expressions. It provides enterprise-grade features including job prioritization, rate limiting, timezone support, dead letter queue management, and a beautiful web UI.

## Why TimeOS?

TimeOS solves the complexity of job scheduling in Elixir applications by providing:

- **Declarative DSL** - Write rules that read like English
- **Event-Driven** - Trigger jobs based on application events
- **Production-Ready** - Built-in retry logic, timeouts, concurrency limits, and graceful shutdown
- **Observable** - Health checks, telemetry, and web UI for monitoring
- **Flexible** - Support for timezones, dependencies, batch operations, and more

## Installation

Add TimeOS to your `mix.exs`:

```elixir
def deps do
  [
    {:timeos, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
mix ecto.setup
```

## Quick Start

### 1. Define Your Rules

Create a module with your temporal rules using the intuitive DSL:

```elixir
defmodule MyApp.Rules do
  use TimeOS.DSL.RuleSet

  # Event-driven: Trigger after an event occurs
  on_event :user_signup, offset: days(2) do
    perform :send_welcome_email
  end

  # Periodic: Run every X minutes/hours/days
  every hours(1) do
    perform :check_system_health
  end

  # Cron: Full cron expression support
  cron "0 9 * * 1", timezone: "America/New_York" do
    perform :monday_morning_report
  end

  # Day-of-week helpers: Because cron is hard
  every_monday at: "09:00", timezone: "America/New_York" do
    perform :send_weekly_newsletter
  end
end
```

### 2. Register Rules and Performer

```elixir
# Load rules from your module
TimeOS.load_rules_from_module(MyApp.Rules)

# Register a performer to handle actions
defmodule MyApp.Performer do
  def perform(:send_welcome_email, payload) do
    user_id = payload["user_id"]
    Email.send_welcome(user_id)
    :ok
  end

  def perform(:check_system_health, _payload) do
    HealthChecker.check()
    :ok
  end

  def perform(:monday_morning_report, _payload) do
    Report.generate_and_send()
    :ok
  end
end

TimeOS.register_performer(MyApp.Performer)
```

### 3. Emit Events

```elixir
# Emit an event
TimeOS.emit(:user_signup, %{"user_id" => "123"})

# With idempotency key to prevent duplicates
TimeOS.emit(:user_signup, %{"user_id" => "123"}, 
  idempotency_key: "unique-key-123")
```

That's it! Your jobs are automatically scheduled and will execute when due.

## Core Features

### Event-Driven Scheduling

Trigger jobs after events occur with configurable delays:

```elixir
on_event :order_placed, offset: minutes(15) do
  perform :send_order_confirmation
end

on_event :payment_received, offset: hours(24), when: fn payload ->
  payload["amount"] > 1000
end do
  perform :send_premium_receipt
end
```

**Options:**
- `offset`: Delay before executing (use `days()`, `hours()`, `minutes()`, `seconds()`)
- `when`: Conditional function that receives the event payload

### Periodic Jobs

Run jobs at regular intervals:

```elixir
every minutes(30) do
  perform :check_system_health
end

every hours(1), timezone: "UTC" do
  perform :sync_data
end
```

### Cron Scheduling

Use standard cron expressions with timezone support:

```elixir
cron "0 9 * * 1", timezone: "America/New_York" do
  perform :monday_morning_report
end

cron "0 */6 * * *" do
  perform :check_backups
end
```

**Cron Format:** `minute hour day_of_month month day_of_week`

### Day-of-Week Helpers

Convenient helpers for weekly schedules:

```elixir
every_monday at: "09:00", timezone: "America/New_York" do
  perform :send_newsletter
end

every_tuesday at: "14:30" do
  perform :team_meeting_reminder
end

# All days supported: every_monday, every_tuesday, every_wednesday,
# every_thursday, every_friday, every_saturday, every_sunday
```

**Options:**
- `at`: Time in "HH:MM" format (24-hour)
- `timezone`: Timezone for the schedule (defaults to UTC)

## Advanced Features

### Job Prioritization

Execute critical jobs first by setting priority levels:

```elixir
rule = TimeOS.list_rules() |> Enum.find(&(&1.name =~ "critical_alert"))
TimeOS.update_rule(rule.id, %{priority: 100})
```

Higher priority jobs execute first. Default priority is 0.

### Rate Limiting

Prevent overwhelming external APIs or services:

```elixir
rule = TimeOS.list_rules() |> Enum.find(&(&1.name =~ "send_email"))
TimeOS.update_rule(rule.id, %{rate_limit_per_minute: 10})
```

This limits the rule to 10 executions per minute using a token bucket algorithm.

### Per-Rule Concurrency Limits

Control how many jobs from a rule can run simultaneously:

```elixir
rule = TimeOS.list_rules() |> Enum.find(&(&1.name =~ "process_data"))
TimeOS.update_rule(rule.id, %{concurrency_limit: 5})
```

This ensures at most 5 jobs from this rule run concurrently. Other jobs wait until a slot becomes available.

### Job Timeouts

Prevent jobs from running indefinitely:

```elixir
# In your rule DSL
on_event :process_large_file, offset: seconds(0) do
  perform :process_file, timeout_seconds: 300  # 5 minutes
end
```

Jobs exceeding their timeout are automatically marked as failed and can be retried according to the retry policy.

### Job Dependencies

Chain jobs together so one job waits for another to complete:

```elixir
# When creating jobs programmatically
job_a = %{
  rule_id: rule.id,
  perform_at: DateTime.utc_now(),
  status: :pending,
  args: %{"action" => "process_data"}
}

job_b = %{
  rule_id: rule.id,
  perform_at: DateTime.utc_now(),
  status: :pending,
  depends_on_job_id: job_a.id,  # Job B waits for Job A
  args: %{"action" => "send_notification"}
}
```

### Event Deduplication

Prevent duplicate events using idempotency keys:

```elixir
# First call creates the event
{:ok, event_id1} = TimeOS.emit(:payment_received, %{"amount" => 100}, 
  idempotency_key: "payment-123")

# Second call with same key returns existing event ID
{:ok, event_id2} = TimeOS.emit(:payment_received, %{"amount" => 100}, 
  idempotency_key: "payment-123")

# event_id1 == event_id2
```

### Dead Letter Queue

Jobs that fail after max attempts are moved to the dead letter queue:

```elixir
# List dead letter jobs
dead_jobs = TimeOS.list_dead_letter_jobs()

# Inspect and retry
for job <- dead_jobs do
  IO.inspect(job.last_error)
  TimeOS.retry_dead_letter_job(job.id)
end

# Or permanently delete
TimeOS.delete_dead_letter_job(job.id)
```

### Batch Operations

Emit multiple events or cancel multiple jobs at once:

```elixir
# Emit multiple events
events = [
  {:user_signup, %{"user_id" => "1"}},
  {:user_signup, %{"user_id" => "2"}},
  {:user_signup, %{"user_id" => "3"}}
]
results = TimeOS.emit_batch(events)
# Returns: [{event_id1, :ok}, {event_id2, :ok}, {event_id3, :ok}]

# Cancel multiple jobs
TimeOS.cancel_jobs_batch(["job-1", "job-2", "job-3"])
```

## Monitoring & Observability

### Web UI

TimeOS includes a beautiful web interface for monitoring jobs in real-time.

**Enable the UI:**

```elixir
# config/dev.exs
config :timeos, enable_ui: true
config :timeos, ui_port: 4000
```

**Enable Authentication (Recommended for Production):**

```elixir
# Basic Auth
config :timeos, ui_auth_enabled: true
config :timeos, ui_username: "admin"
config :timeos, ui_password: "your-secure-password"

# Or API Key
config :timeos, ui_auth_enabled: true
config :timeos, ui_api_key: "your-api-key-here"
```

Then start your application and visit `http://localhost:4000`.

**Features:**
- Real-time job dashboard with status badges
- System health indicators
- Metrics overview (pending, running, failed jobs, etc.)
- Filter jobs by status
- Auto-refresh capability

### Health Checks

Monitor system health and component status:

```elixir
health = TimeOS.health_check()

# Returns:
# %{
#   status: :healthy | :degraded,
#   components: %{
#     database: %{status: :healthy, message: "..."},
#     rule_registry: %{status: :healthy, message: "..."},
#     evaluator: %{status: :healthy, message: "..."},
#     scheduler: %{status: :healthy, message: "..."},
#     rate_limiter: %{status: :healthy, message: "..."}
#   },
#   metrics: %{
#     pending_jobs: 10,
#     running_jobs: 2,
#     failed_jobs: 0,
#     dead_letter_jobs: 1,
#     total_rules: 5,
#     enabled_rules: 4
#   }
# }
```

### Telemetry

TimeOS emits telemetry events for observability:

```elixir
# Events automatically tracked:
# - [:timeos, :event, :emitted]
# - [:timeos, :job, :created]
# - [:timeos, :job, :started]
# - [:timeos, :job, :completed]
# - [:timeos, :job, :failed]
# - [:timeos, :rule, :matched]
# - [:timeos, :rate_limit, :exceeded]
# - [:timeos, :concurrency_limit, :exceeded]

# Attach your own handlers
:telemetry.attach("my-handler", [:timeos, :job, :completed], 
  fn event, measurements, metadata ->
    # Handle job completion
  end)
```

## Configuration

### Database Setup

TimeOS uses Ecto for database persistence. Configure your database:

```elixir
# config/dev.exs
config :timeos, TimeOS.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "timeos_dev",
  pool_size: 10
```

### Production Configuration

For production, use environment variables:

```elixir
# config/prod.exs
config :timeos, TimeOS.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "20"))
```

**Environment Variables:**
- `DATABASE_URL`: PostgreSQL connection string
- `POOL_SIZE`: Database connection pool size (default: 20)
- `LOG_LEVEL`: Logging level - `debug`, `info`, `warn`, `error` (default: `info`)
- `ENABLE_UI`: Enable web UI (default: `false`)
- `UI_PORT`: Web UI port (default: `4000`)

### Data Cleanup

Prevent database bloat with automatic cleanup:

```elixir
# config/dev.exs
config :timeos,
  enable_cleanup_scheduler: true,
  cleanup_interval_ms: 24 * 60 * 60 * 1000,  # 24 hours
  events_retention_days: 90,
  success_jobs_retention_days: 30,
  failed_jobs_retention_days: 7
```

**Manual Cleanup:**

```elixir
# Clean up with default retention periods
TimeOS.cleanup()

# Clean up with custom retention periods
TimeOS.cleanup(
  events_retention_days: 60,
  success_jobs_retention_days: 14,
  failed_jobs_retention_days: 3
)

# Get cleanup statistics
stats = TimeOS.cleanup_stats()
# Returns: %{old_events: 150, old_successful_jobs: 45, ...}
```

**Note:** Dead letter queue jobs are never automatically cleaned up. You must manually manage them using `TimeOS.delete_dead_letter_job/1`.

## API Reference

### Events

```elixir
# Emit an event
TimeOS.emit(:event_type, %{"key" => "value"})
TimeOS.emit(:event_type, %{"key" => "value"}, 
  occurred_at: DateTime.utc_now(), 
  idempotency_key: "unique-key")

# Batch emit
TimeOS.emit_batch([
  {:event1, %{"data" => 1}},
  {:event2, %{"data" => 2}}
])

# Query events
TimeOS.list_events(type: "user_signup", processed: false, limit: 100)
TimeOS.get_event(event_id)
TimeOS.replay_event(event_id)
```

### Jobs

```elixir
# List and manage jobs
TimeOS.list_jobs(status: :pending, limit: 100, rule_id: rule_id)
TimeOS.get_job(job_id)
TimeOS.cancel_job(job_id)
TimeOS.cancel_jobs_batch([job_id1, job_id2])
```

### Rules

```elixir
TimeOS.load_rules_from_module(MyApp.Rules)
TimeOS.list_rules()
TimeOS.get_rule(rule_id)
TimeOS.enable_rule(rule_id, true)
TimeOS.update_rule(rule_id, %{
  priority: 10, 
  rate_limit_per_minute: 5,
  concurrency_limit: 3
})
TimeOS.delete_rule(rule_id)
TimeOS.reload_rules()
```

### Dead Letter Queue

```elixir
TimeOS.list_dead_letter_jobs(rule_id: rule_id, limit: 50)
TimeOS.retry_dead_letter_job(job_id)
TimeOS.delete_dead_letter_job(job_id)
```

## Real-World Examples

### E-commerce Order Processing

```elixir
defmodule Ecommerce.Rules do
  use TimeOS.DSL.RuleSet

  on_event :order_placed, offset: minutes(15) do
    perform :send_order_confirmation
  end

  on_event :order_placed, offset: hours(24) do
    perform :request_review
  end

  on_event :order_shipped, offset: days(7) do
    perform :request_feedback
  end

  every_monday at: "08:00", timezone: "America/New_York" do
    perform :send_weekly_sales_report
  end
end
```

### User Engagement

```elixir
defmodule Engagement.Rules do
  use TimeOS.DSL.RuleSet

  on_event :user_signup, offset: hours(1) do
    perform :send_onboarding_email
  end

  on_event :user_signup, offset: days(3) do
    perform :check_activation
  end

  on_event :user_inactive, offset: days(7) do
    perform :send_reactivation_email
  end

  cron "0 10 * * *", timezone: "UTC" do
    perform :daily_engagement_analysis
  end
end
```

### System Maintenance

```elixir
defmodule Maintenance.Rules do
  use TimeOS.DSL.RuleSet

  every hours(1) do
    perform :check_system_health
  end

  every days(1), timezone: "UTC" do
    perform :backup_database
  end

  every_sunday at: "02:00", timezone: "America/New_York" do
    perform :weekly_maintenance
  end

  cron "0 0 1 * *" do
    perform :monthly_cleanup
  end
end
```

## Architecture

TimeOS consists of several key components:

- **Evaluator**: Matches events against rules and creates scheduled jobs
- **Scheduler**: Polls for due jobs and spawns workers, checks dependencies and limits
- **JobWorker**: Executes jobs with retry logic, timeout handling, and graceful shutdown
- **RuleRegistry**: Manages rules and performer callbacks
- **RateLimiter**: Enforces rate limits using token bucket algorithm
- **ConcurrencyTracker**: Tracks and enforces per-rule concurrency limits
- **CronParser**: Parses and calculates next execution times for cron expressions
- **EventReceiver**: Receives and forwards events to the evaluator
- **Health**: Monitors system health and component status
- **Telemetry**: Tracks events and job lifecycle for observability
- **Web**: Provides web UI for job monitoring (optional)
- **Cleanup**: Automatic and manual data cleanup to prevent database bloat

## Testing

Run the test suite:

```bash
mix test
```

TimeOS includes comprehensive tests for all features including event emission, rule matching, job scheduling, dead letter queue, rate limiting, timezone handling, cron parsing, event deduplication, job dependencies, batch operations, health checks, data cleanup, timeouts, concurrency limits, and integration tests.

## Documentation

Generate documentation using ExDoc:

```bash
mix docs
```

This generates HTML documentation in the `doc/` directory with complete API reference, module grouping by category, and code examples.

## Graceful Shutdown

TimeOS automatically handles graceful shutdown:
- Waits for in-flight jobs to complete (up to 5 seconds)
- Reverts running jobs to pending status if worker crashes
- Logs warnings for jobs still running after grace period

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
