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

## API Reference

### Events

```elixir
TimeOS.emit(:event_type, %{"key" => "value"})
TimeOS.emit(:event_type, %{"key" => "value"}, occurred_at: DateTime.utc_now())
```

### Jobs

```elixir
TimeOS.list_jobs(status: :pending, limit: 100)
TimeOS.get_job(job_id)
TimeOS.cancel_job(job_id)
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
```

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

## Architecture

TimeOS consists of several key components:

- **Evaluator**: Matches events against rules and creates scheduled jobs
- **Scheduler**: Polls for due jobs and spawns workers
- **JobWorker**: Executes jobs with retry logic
- **RuleRegistry**: Manages rules and performer callbacks
- **RateLimiter**: Enforces rate limits using token bucket algorithm
- **CronParser**: Parses and calculates next execution times for cron expressions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
