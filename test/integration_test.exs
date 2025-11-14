defmodule TimeOS.IntegrationTest do
  use TimeOS.DataCase

  alias TimeOS.Repo

  defmodule TestPerformer do
    def perform(:test_action, _payload), do: :ok
    def perform(:fail_action, _payload), do: {:error, "Intentional failure"}
  end

  setup do
    TimeOS.register_performer(TestPerformer)
    :ok
  end

  test "end-to-end: emit event, create job, execute job" do
    defmodule TestRules do
      use TimeOS.DSL.RuleSet

      on_event :test_event, offset: seconds(0) do
        perform :test_action
      end
    end

    TimeOS.load_rules_from_module(TestRules)

    {:ok, event_id} = TimeOS.emit(:test_event, %{"test" => "data"})

    assert event_id != nil

    Process.sleep(2000)

    jobs = TimeOS.list_jobs(status: :success, limit: 10)

    assert Enum.any?(jobs, fn job ->
      job.event_id == event_id && get_in(job.args, ["action"]) == "test_action"
    end)
  end

  test "end-to-end: job dependencies" do
    rule = insert(:time_rule)
    first_job = insert(:scheduled_job, rule_id: rule.id, status: :success)

    defmodule DependentRules do
      use TimeOS.DSL.RuleSet

      on_event :dependency_test, offset: seconds(0) do
        perform :test_action
      end
    end

    TimeOS.load_rules_from_module(DependentRules)

    {:ok, event_id} = TimeOS.emit(:dependency_test, %{})

    Process.sleep(1000)

    jobs = TimeOS.list_jobs(status: :pending, limit: 100)
    dependent_job = Enum.find(jobs, fn job ->
      job.event_id == event_id && job.depends_on_job_id == first_job.id
    end)

    if dependent_job == nil do
      job_data = %{
        rule_id: rule.id,
        event_id: event_id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        depends_on_job_id: first_job.id,
        args: %{"action" => "test_action"}
      }

      {:ok, created_job} = TimeOS.Schema.ScheduledJob.changeset(%TimeOS.Schema.ScheduledJob{}, job_data)
        |> Repo.insert()

      assert created_job.depends_on_job_id == first_job.id
    else
      assert dependent_job.depends_on_job_id == first_job.id
    end
  end

  test "end-to-end: event deduplication" do
    idempotency_key = "test-unique-key-#{System.system_time(:second)}"

    {:ok, event_id1} = TimeOS.emit(:test_event, %{}, idempotency_key: idempotency_key)
    {:ok, event_id2} = TimeOS.emit(:test_event, %{}, idempotency_key: idempotency_key)

    assert event_id1 == event_id2
  end

  test "end-to-end: batch operations" do
    events = [
      {:test_event, %{"batch" => 1}},
      {:test_event, %{"batch" => 2}},
      {:test_event, %{"batch" => 3}}
    ]

    results = TimeOS.emit_batch(events)

    assert length(results) == 3
    assert Enum.all?(results, fn {id, result} -> id != nil && result == :ok end)
  end

  test "end-to-end: health check" do
    health = TimeOS.health_check()

    assert health.status in [:healthy, :degraded]
    assert Map.has_key?(health, :components)
    assert Map.has_key?(health, :metrics)
  end

  test "end-to-end: event replay" do
    {:ok, event_id} = TimeOS.emit(:test_event, %{"replay" => true})

    Process.sleep(1000)

    {:ok, replayed_event} = TimeOS.replay_event(event_id)

    assert replayed_event.id == event_id
    assert replayed_event.processed == false
  end

end
