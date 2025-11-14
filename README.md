# TimeOS

TimeOS is a powerful temporal rule engine for Elixir that enables you to schedule jobs based on events, time intervals, and cron expressions. It provides enterprise-grade features including job prioritization, rate limiting, timezone support, and dead letter queue management.

## Features

- **Event-Driven Scheduling**: Trigger jobs based on events with configurable delays
- **Periodic Jobs**: Schedule jobs to run at regular intervals
- **Cron Scheduling**: Full cron expression support with convenient day-of-week helpers
- **Job Prioritization**: Execute jobs based on priority levels
- **Rate Limiting**: Per-rule and per-action rate limiting
- **Timezone Support**: Schedule jobs in any timezone
- **Dead Letter Queue**: Automatic handling of permanently failed jobs
- **Retry Logic**: Exponential backoff with configurable max attempts
- **Conditional Rules**: Filter events with `when` clauses
- **Event Deduplication**: Prevent duplicate events with idempotency keys
- **Job Dependencies**: Chain jobs together (job A triggers job B)
- **Batch Operations**: Emit multiple events or cancel multiple jobs at once
- **Event Querying**: Query and replay events
- **Health Checks**: Monitor system health and component status
- **Telemetry**: Built-in observability with event tracking
- **Graceful Shutdown**: Safely handle in-flight jobs during shutdown
- **Web UI**: Beautiful dashboard for monitoring jobs in real-time

## Installation

Add TimeOS to your `mix.exs`:

```elixir
def deps do
  [
    {:timeos, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get` and `mix ecto.setup`.

## Quick Start

### 1. Define Your Rules

Create a module with your temporal rules:

```elixir
defmodule MyApp.Rules do
  use TimeOS.DSL.RuleSet

  on_event :user_signup, offset: days(2) do
    perform :send_welcome_email
  end

  every_monday at: "09:00", timezone: "America/New_York" do
    perform :send_weekly_report
  end

  cron "0 0 * * *", timezone: "UTC" do
    perform :daily_cleanup
  end
end
```

### 2. Register Your Rules

```elixir
TimeOS.load_rules_from_module(MyApp.Rules)
```

### 3. Create a Performer

Implement the actions your rules will execute:

```elixir
defmodule MyApp.Performer do
  def perform(:send_welcome_email, payload) do
    user_id = payload["user_id"]
    Email.send_welcome(user_id)
    :ok
  end

  def perform(:send_weekly_report, _payload) do
    Report.generate_and_send()
    :ok
  end

  def perform(:daily_cleanup, _payload) do
    Database.cleanup_old_records()
    :ok
  end
end
```

### 4. Register the Performer

```elixir
TimeOS.register_performer(MyApp.Performer)
```

### 5. Emit Events

```elixir
TimeOS.emit(:user_signup, %{"user_id" => "123"})

# With idempotency key to prevent duplicates
TimeOS.emit(:user_signup, %{"user_id" => "123"}, idempotency_key: "unique-key-123")
```

## DSL Reference

### Event-Based Rules

Trigger jobs after an event occurs:

```elixir
on_event :user_signup, offset: days(2) do
  perform :send_welcome_email
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

### Periodic Rules

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

Use standard cron expressions:

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

every_wednesday do
  perform :midweek_check
end

every_thursday do
  perform :thursday_task
end

every_friday do
  perform :weekend_prep
end

every_saturday do
  perform :saturday_maintenance
end

every_sunday do
  perform :sunday_review
end
```

**Options:**
- `at`: Time in "HH:MM" format (24-hour)
- `timezone`: Timezone for the schedule

## Advanced Features

### Job Prioritization

Set priority levels for jobs:

```elixir
defmodule MyApp.PriorityRules do
  use TimeOS.DSL.RuleSet

  on_event :critical_alert, offset: seconds(0) do
    perform :handle_critical_alert
  end
end

rule = TimeOS.list_rules() |> Enum.find(&(&1.name =~ "critical_alert"))
TimeOS.update_rule(rule.id, %{priority: 100})
```

Higher priority jobs execute first. Default priority is 0.

### Rate Limiting

Limit execution rate per rule:

```elixir
rule = TimeOS.list_rules() |> Enum.find(&(&1.name =~ "send_email"))
TimeOS.update_rule(rule.id, %{rate_limit_per_minute: 10})
```

This limits the rule to 10 executions per minute.

### Timezone Support

Schedule jobs in specific timezones:

```elixir
every_monday at: "09:00", timezone: "America/New_York" do
  perform :morning_report
end

cron "0 12 * * *", timezone: "Europe/London" do
  perform :lunch_reminder
end
```

### Dead Letter Queue

Jobs that fail after max attempts are moved to the dead letter queue:

```elixir
dead_jobs = TimeOS.list_dead_letter_jobs()

for job <- dead_jobs do
  IO.inspect(job.last_error)
  
  TimeOS.retry_dead_letter_job(job.id)
end
```

**API:**
- `TimeOS.list_dead_letter_jobs(filters \\ [])` - List dead letter jobs
- `TimeOS.retry_dead_letter_job(job_id)` - Retry a dead letter job
- `TimeOS.delete_dead_letter_job(job_id)` - Permanently delete a dead letter job

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

### Job Dependencies

Chain jobs together so one job waits for another to complete:

```elixir
# Job B depends on Job A
job_a = %{
  rule_id: rule.id,
  perform_at: DateTime.utc_now(),
  status: :pending,
  args: %{"action" => "process_data"}
}

# Job B will wait for Job A to succeed
job_b = %{
  rule_id: rule.id,
  perform_at: DateTime.utc_now(),
  status: :pending,
  depends_on_job_id: job_a.id,
  args: %{"action" => "send_notification"}
}
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
job_ids = ["job-1", "job-2", "job-3"]
TimeOS.cancel_jobs_batch(job_ids)
```

### Event Querying and Replay

Query events and replay them if needed:

```elixir
# List events with filters
events = TimeOS.list_events(type: "user_signup", limit: 50)

# Get a specific event
event = TimeOS.get_event(event_id)

# Replay an event (re-evaluate against rules)
{:ok, replayed_event} = TimeOS.replay_event(event_id)
```

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

### Web UI

TimeOS includes a beautiful web interface for monitoring jobs in real-time:

1. Enable the UI in `config/dev.exs`:
```elixir
config :timeos, enable_ui: true
config :timeos, ui_port: 4000
```

2. Start your application:
```bash
mix run --no-halt
```

3. Open your browser to `http://localhost:4000`

The UI provides:
- Real-time job dashboard with status badges
- System health indicators
- Metrics overview (pending, running, failed jobs, etc.)
- Filter jobs by status
- Auto-refresh capability
- Beautiful modern design

### Telemetry

TimeOS emits telemetry events for observability:

```elixir
# Events are automatically tracked:
# - [:timeos, :event, :emitted]
# - [:timeos, :job, :created]
# - [:timeos, :job, :started]
# - [:timeos, :job, :completed]
# - [:timeos, :job, :failed]
# - [:timeos, :rule, :matched]
# - [:timeos, :rate_limit, :exceeded]

# Attach your own handlers
:telemetry.attach("my-handler", [:timeos, :job, :completed], fn event, measurements, metadata ->
  # Handle job completion
end)
```

## API Reference

### Events

```elixir
# Emit an event
TimeOS.emit(:event_type, %{"key" => "value"})
TimeOS.emit(:event_type, %{"key" => "value"}, occurred_at: DateTime.utc_now())
TimeOS.emit(:event_type, %{"key" => "value"}, idempotency_key: "unique-key")

# Batch emit
TimeOS.emit_batch([
  {:event1, %{"data" => 1}},
  {:event2, %{"data" => 2}}
])

# Query events
TimeOS.list_events(type: "user_signup", processed: false, limit: 100, offset: 0)
TimeOS.get_event(event_id)

# Replay events
TimeOS.replay_event(event_id)
```

### Jobs

```elixir
# List and manage jobs
TimeOS.list_jobs(status: :pending, limit: 100, rule_id: rule_id, event_id: event_id)
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
TimeOS.update_rule(rule_id, %{priority: 10, rate_limit_per_minute: 5})
TimeOS.delete_rule(rule_id)
TimeOS.reload_rules()
```

### Dead Letter Queue

```elixir
TimeOS.list_dead_letter_jobs(rule_id: rule_id, limit: 50)
TimeOS.retry_dead_letter_job(job_id)
TimeOS.delete_dead_letter_job(job_id)
```

### Health and Monitoring

```elixir
# Check system health
TimeOS.health_check()
# Returns health status, component checks, and metrics
```

## Examples

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

## Configuration

TimeOS uses Ecto for database persistence. Configure your database in `config/dev.exs`:

```elixir
config :timeos, TimeOS.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "timeos_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Enable web UI (optional)
config :timeos, enable_ui: true
config :timeos, ui_port: 4000
```

### Graceful Shutdown

TimeOS automatically handles graceful shutdown:
- Waits for in-flight jobs to complete (up to 5 seconds)
- Reverts running jobs to pending status if worker crashes
- Logs warnings for jobs still running after grace period

## Testing

Run the test suite:

```bash
mix test
```

TimeOS includes comprehensive tests for all features including:
- Event emission and rule matching
- Job scheduling and execution
- Dead letter queue
- Rate limiting
- Timezone handling
- Cron parsing
- Event deduplication
- Job dependencies
- Batch operations
- Health checks
- Integration tests

## Architecture

TimeOS consists of several key components:

- **Evaluator**: Matches events against rules and creates scheduled jobs
- **Scheduler**: Polls for due jobs and spawns workers, checks dependencies
- **JobWorker**: Executes jobs with retry logic and graceful shutdown handling
- **RuleRegistry**: Manages rules and performer callbacks
- **RateLimiter**: Enforces rate limits using token bucket algorithm
- **CronParser**: Parses and calculates next execution times for cron expressions
- **EventReceiver**: Receives and forwards events to the evaluator
- **Health**: Monitors system health and component status
- **Telemetry**: Tracks events and job lifecycle for observability
- **Web**: Provides web UI for job monitoring (optional)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
