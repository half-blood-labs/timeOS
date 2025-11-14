defmodule TimeOS.Factory do
  use ExMachina.Ecto, repo: TimeOS.Repo

  alias TimeOS.Schema.{TimeRule, Event, ScheduledJob}

  def time_rule_factory do
    %TimeRule{
      name: sequence("rule_"),
      compiled: %{
        "type" => "on_event",
        "event_type" => "test_event",
        "offset_ms" => 0,
        "actions" => [%{"action" => "test_action", "opts" => []}]
      },
      enabled: true,
      priority: 0,
      rate_limit_per_minute: nil,
      timezone: nil,
      cron_expression: nil
    }
  end

  def event_factory do
    %Event{
      type: :test_event,
      payload: %{"user_id" => "123"},
      occurred_at: DateTime.utc_now(),
      processed: false
    }
  end

  def scheduled_job_factory do
    %ScheduledJob{
      rule_id: Ecto.UUID.generate(),
      event_id: Ecto.UUID.generate(),
      perform_at: DateTime.utc_now(),
      attempt_count: 0,
      max_attempts: 3,
      status: :pending,
      priority: 0,
      timezone: nil,
      rate_limit_key: nil,
      dead_letter_queue: false,
      dead_letter_at: nil,
      args: %{
        "action" => "test_action",
        "opts" => [],
        "event_type" => "test_event",
        "payload" => %{}
      }
    }
  end
end
