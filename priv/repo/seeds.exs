alias TimeOS.Repo
alias TimeOS.Schema.{Event, ScheduledJob, TimeRule}

defmodule TimeOS.Seeds do
  def run do
    IO.puts("🌱 Seeding TimeOS database...")

    create_rules()
    create_events()
    create_jobs()

    IO.puts("✅ Seeding complete!")
  end

  defp create_rules do
    rules = [
      %{
        name: "user_signup_welcome_email",
        compiled: %{
          "type" => "on_event",
          "event_type" => "user_signup",
          "offset_ms" => 172_800_000,
          "actions" => [%{"action" => "send_welcome_email", "opts" => []}]
        },
        module: "SampleRules",
        enabled: true,
        priority: 10,
        timezone: "UTC"
      },
      %{
        name: "daily_health_check",
        compiled: %{
          "type" => "every",
          "interval_ms" => 3_600_000,
          "actions" => [%{"action" => "check_system_health", "opts" => []}]
        },
        module: "SampleRules",
        enabled: true,
        priority: 5,
        timezone: "UTC"
      },
      %{
        name: "monday_morning_report",
        compiled: %{
          "type" => "cron",
          "cron_expression" => "0 9 * * 1",
          "actions" => [%{"action" => "send_weekly_report", "opts" => []}]
        },
        module: "SampleRules",
        enabled: true,
        priority: 20,
        timezone: "America/New_York",
        cron_expression: "0 9 * * 1"
      },
      %{
        name: "payment_reminder",
        compiled: %{
          "type" => "on_event",
          "event_type" => "payment_due",
          "offset_ms" => 86_400_000,
          "actions" => [%{"action" => "send_payment_reminder", "opts" => []}]
        },
        module: "SampleRules",
        enabled: true,
        priority: 15,
        rate_limit_per_minute: 5,
        timezone: "UTC"
      },
      %{
        name: "hourly_data_sync",
        compiled: %{
          "type" => "every",
          "interval_ms" => 3_600_000,
          "actions" => [%{"action" => "sync_external_data", "opts" => []}]
        },
        module: "SampleRules",
        enabled: true,
        priority: 0,
        timezone: "UTC"
      }
    ]

    for rule_data <- rules do
      case Repo.get_by(TimeRule, name: rule_data.name) do
        nil ->
          changeset = TimeRule.changeset(%TimeRule{}, rule_data)
          case Repo.insert(changeset) do
            {:ok, rule} ->
              IO.puts("  ✓ Created rule: #{rule.name}")
            {:error, changeset} ->
              IO.puts("  ✗ Failed to create rule #{rule_data.name}: #{inspect(changeset.errors)}")
          end
        _existing ->
          IO.puts("  ⊙ Rule already exists: #{rule_data.name}")
      end
    end
  end

  defp create_events do
    now = DateTime.utc_now()
    
    events = [
      %{
        type: "user_signup",
        payload: %{"user_id" => "user_001", "email" => "alice@example.com", "plan" => "premium"},
        occurred_at: DateTime.add(now, -2, :day),
        processed: true,
        idempotency_key: "user_signup_001"
      },
      %{
        type: "user_signup",
        payload: %{"user_id" => "user_002", "email" => "bob@example.com", "plan" => "basic"},
        occurred_at: DateTime.add(now, -1, :day),
        processed: true,
        idempotency_key: "user_signup_002"
      },
      %{
        type: "user_signup",
        payload: %{"user_id" => "user_003", "email" => "charlie@example.com", "plan" => "premium"},
        occurred_at: DateTime.add(now, -30, :minute),
        processed: false,
        idempotency_key: "user_signup_003"
      },
      %{
        type: "payment_due",
        payload: %{"user_id" => "user_001", "amount" => 99.99, "due_date" => "2025-11-20"},
        occurred_at: DateTime.add(now, -1, :hour),
        processed: true,
        idempotency_key: "payment_due_001"
      },
      %{
        type: "payment_due",
        payload: %{"user_id" => "user_002", "amount" => 29.99, "due_date" => "2025-11-21"},
        occurred_at: now,
        processed: false,
        idempotency_key: "payment_due_002"
      }
    ]

    for event_data <- events do
      case Repo.get_by(Event, idempotency_key: event_data.idempotency_key) do
        nil ->
          changeset = Event.changeset(%Event{}, event_data)
          case Repo.insert(changeset) do
            {:ok, event} ->
              IO.puts("  ✓ Created event: #{event.type} (#{event.idempotency_key})")
            {:error, changeset} ->
              IO.puts("  ✗ Failed to create event: #{inspect(changeset.errors)}")
          end
        _existing ->
          IO.puts("  ⊙ Event already exists: #{event_data.idempotency_key}")
      end
    end
  end

  defp create_jobs do
    rules = Repo.all(TimeRule)
    events = Repo.all(Event)
    
    now = DateTime.utc_now()
    user_signup_rule = Enum.find(rules, &(&1.name == "user_signup_welcome_email"))
    payment_rule = Enum.find(rules, &(&1.name == "payment_reminder"))
    health_rule = Enum.find(rules, &(&1.name == "daily_health_check"))
    report_rule = Enum.find(rules, &(&1.name == "monday_morning_report"))
    sync_rule = Enum.find(rules, &(&1.name == "hourly_data_sync"))

    user_signup_events = Enum.filter(events, &(&1.type == "user_signup"))
    payment_events = Enum.filter(events, &(&1.type == "payment_due"))

    jobs = []

    jobs = if user_signup_rule && length(user_signup_events) > 0 do
      event1 = Enum.at(user_signup_events, 0)
      event2 = Enum.at(user_signup_events, 1)
      _event3 = Enum.at(user_signup_events, 2)

      jobs ++ [
        %{
          rule_id: user_signup_rule.id,
          event_id: if(event1, do: event1.id, else: nil),
          perform_at: DateTime.add(now, 1, :hour),
          status: :pending,
          priority: user_signup_rule.priority,
          attempt_count: 0,
          max_attempts: 3,
          args: %{"action" => "send_welcome_email", "event_type" => "user_signup", "payload" => event1 && event1.payload || %{}},
          timezone: user_signup_rule.timezone
        },
        %{
          rule_id: user_signup_rule.id,
          event_id: if(event2, do: event2.id, else: nil),
          perform_at: DateTime.add(now, -30, :minute),
          status: :running,
          priority: user_signup_rule.priority,
          attempt_count: 1,
          max_attempts: 3,
          args: %{"action" => "send_welcome_email", "event_type" => "user_signup", "payload" => event2 && event2.payload || %{}},
          timezone: user_signup_rule.timezone
        },
        %{
          rule_id: user_signup_rule.id,
          event_id: if(event1, do: event1.id, else: nil),
          perform_at: DateTime.add(now, -2, :hour),
          status: :success,
          priority: user_signup_rule.priority,
          attempt_count: 1,
          max_attempts: 3,
          args: %{"action" => "send_welcome_email", "event_type" => "user_signup", "payload" => event1 && event1.payload || %{}},
          timezone: user_signup_rule.timezone,
          result: %{"status" => "success", "completed_at" => DateTime.to_iso8601(DateTime.add(now, -1, :hour))}
        },
        %{
          rule_id: user_signup_rule.id,
          event_id: if(event2, do: event2.id, else: nil),
          perform_at: DateTime.add(now, -3, :hour),
          status: :failed,
          priority: user_signup_rule.priority,
          attempt_count: 2,
          max_attempts: 3,
          args: %{"action" => "send_welcome_email", "event_type" => "user_signup", "payload" => event2 && event2.payload || %{}},
          timezone: user_signup_rule.timezone,
          last_error: "SMTP connection timeout"
        }
      ]
    else
      jobs
    end

    jobs = if payment_rule && length(payment_events) > 0 do
      payment_event = Enum.at(payment_events, 0)

      jobs ++ [
        %{
          rule_id: payment_rule.id,
          event_id: if(payment_event, do: payment_event.id, else: nil),
          perform_at: DateTime.add(now, 2, :hour),
          status: :pending,
          priority: payment_rule.priority,
          attempt_count: 0,
          max_attempts: 3,
          args: %{"action" => "send_payment_reminder", "event_type" => "payment_due", "payload" => payment_event && payment_event.payload || %{}},
          timezone: payment_rule.timezone,
          rate_limit_key: "rule:#{payment_rule.id}:action:send_payment_reminder"
        },
        %{
          rule_id: payment_rule.id,
          event_id: if(payment_event, do: payment_event.id, else: nil),
          perform_at: DateTime.add(now, -1, :day),
          status: :dead,
          priority: payment_rule.priority,
          attempt_count: 3,
          max_attempts: 3,
          args: %{"action" => "send_payment_reminder", "event_type" => "payment_due", "payload" => payment_event && payment_event.payload || %{}},
          timezone: payment_rule.timezone,
          last_error: "Email service unavailable after 3 attempts",
          dead_letter_queue: true,
          dead_letter_at: DateTime.add(now, -1, :day)
        }
      ]
    else
      jobs
    end

    jobs = if health_rule do
      jobs ++ [
        %{
          rule_id: health_rule.id,
          event_id: nil,
          perform_at: DateTime.add(now, 30, :minute),
          status: :pending,
          priority: health_rule.priority,
          attempt_count: 0,
          max_attempts: 3,
          args: %{"action" => "check_system_health", "event_type" => nil, "payload" => %{}},
          timezone: health_rule.timezone
        },
        %{
          rule_id: health_rule.id,
          event_id: nil,
          perform_at: DateTime.add(now, -1, :hour),
          status: :success,
          priority: health_rule.priority,
          attempt_count: 1,
          max_attempts: 3,
          args: %{"action" => "check_system_health", "event_type" => nil, "payload" => %{}},
          timezone: health_rule.timezone,
          result: %{"status" => "success", "health_score" => 98, "completed_at" => DateTime.to_iso8601(DateTime.add(now, -55, :minute))}
        }
      ]
    else
      jobs
    end

    jobs = if report_rule do
      next_monday = calculate_next_monday(now)
      
      jobs ++ [
        %{
          rule_id: report_rule.id,
          event_id: nil,
          perform_at: next_monday,
          status: :pending,
          priority: report_rule.priority,
          attempt_count: 0,
          max_attempts: 3,
          args: %{"action" => "send_weekly_report", "event_type" => nil, "payload" => %{}},
          timezone: report_rule.timezone
        }
      ]
    else
      jobs
    end

    jobs = if sync_rule do
      jobs ++ [
        %{
          rule_id: sync_rule.id,
          event_id: nil,
          perform_at: DateTime.add(now, 15, :minute),
          status: :pending,
          priority: sync_rule.priority,
          attempt_count: 0,
          max_attempts: 3,
          args: %{"action" => "sync_external_data", "event_type" => nil, "payload" => %{}},
          timezone: sync_rule.timezone
        }
      ]
    else
      jobs
    end

    for job_data <- jobs do
      changeset = ScheduledJob.changeset(%ScheduledJob{}, job_data)
      case Repo.insert(changeset) do
        {:ok, job} ->
          status_emoji = case job.status do
            :pending -> "⏳"
            :running -> "🔄"
            :success -> "✅"
            :failed -> "❌"
            :dead -> "💀"
          end
          IO.puts("  #{status_emoji} Created job: #{get_in(job.args, ["action"])} (#{job.status})")
        {:error, changeset} ->
          IO.puts("  ✗ Failed to create job: #{inspect(changeset.errors)}")
      end
    end
  end

  defp calculate_next_monday(now) do
    day_of_week = Date.day_of_week(DateTime.to_date(now))
    days_until_monday = if day_of_week == 1, do: 7, else: 8 - day_of_week
    
    next_monday_date = now
    |> DateTime.to_date()
    |> Date.add(days_until_monday)
    
    next_monday = DateTime.new!(next_monday_date, ~T[09:00:00], "Etc/UTC")
    
    case TimeOS.TimezoneUtils.to_timezone(next_monday, "America/New_York") do
      {:ok, ny_time} ->
        case TimeOS.TimezoneUtils.to_utc(ny_time) do
          {:ok, utc_dt} -> utc_dt
          _ -> next_monday
        end
      _ -> next_monday
    end
  end
end

TimeOS.Seeds.run()

