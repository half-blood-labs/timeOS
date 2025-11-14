defmodule ConcurrencyLimitTest do
  use TimeOS.DataCase

  alias TimeOS.Schema.{ScheduledJob, TimeRule}
  alias TimeOS.Repo
  alias TimeOS.ConcurrencyTracker

  setup do
    # Ensure ConcurrencyTracker is started
    case Process.whereis(TimeOS.ConcurrencyTracker) do
      nil -> ConcurrencyTracker.start_link([])
      _pid -> :ok
    end

    rule = insert(:time_rule, concurrency_limit: 2)
    {:ok, rule: rule}
  end

  describe "Concurrency limiting" do
    test "allows jobs within concurrency limit", %{rule: rule} do
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule.id, 2)
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule.id, 2)
    end

    test "blocks jobs when concurrency limit exceeded", %{rule: rule} do
      # Increment to reach limit
      assert {:ok, 1} = ConcurrencyTracker.increment(rule.id)
      assert {:ok, 2} = ConcurrencyTracker.increment(rule.id)

      # Now should be at limit
      assert {:error, :limit_exceeded} = ConcurrencyTracker.check_limit(rule.id, 2)
    end

    test "allows jobs when limit is nil or 0", %{rule: rule} do
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule.id, nil)
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule.id, 0)
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule.id, -1)
    end

    test "tracks concurrent executions per rule", %{rule: rule} do
      # Start with 0
      assert 0 = ConcurrencyTracker.get_count(rule.id)

      # Increment
      assert {:ok, 1} = ConcurrencyTracker.increment(rule.id)
      assert 1 = ConcurrencyTracker.get_count(rule.id)

      # Increment again
      assert {:ok, 2} = ConcurrencyTracker.increment(rule.id)
      assert 2 = ConcurrencyTracker.get_count(rule.id)

      # Decrement
      ConcurrencyTracker.decrement(rule.id)
      assert 1 = ConcurrencyTracker.get_count(rule.id)

      # Decrement again
      ConcurrencyTracker.decrement(rule.id)
      assert 0 = ConcurrencyTracker.get_count(rule.id)
    end

    test "different rules have separate concurrency limits" do
      rule1 = insert(:time_rule, concurrency_limit: 2)
      rule2 = insert(:time_rule, concurrency_limit: 3)

      # Fill up rule1
      assert {:ok, 1} = ConcurrencyTracker.increment(rule1.id)
      assert {:ok, 2} = ConcurrencyTracker.increment(rule1.id)
      assert {:error, :limit_exceeded} = ConcurrencyTracker.check_limit(rule1.id, 2)

      # rule2 should still have capacity
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(rule2.id, 3)
      assert {:ok, 1} = ConcurrencyTracker.increment(rule2.id)
      assert {:ok, 2} = ConcurrencyTracker.increment(rule2.id)
      assert {:ok, 3} = ConcurrencyTracker.increment(rule2.id)
      assert {:error, :limit_exceeded} = ConcurrencyTracker.check_limit(rule2.id, 3)
    end

    test "scheduler respects concurrency limits", %{rule: rule} do
      # Update rule with concurrency limit
      Repo.update!(TimeRule.changeset(rule, %{concurrency_limit: 1}))

      # Create multiple jobs for the same rule
      jobs =
        for _i <- 1..3 do
          insert(:scheduled_job,
            rule_id: rule.id,
            perform_at: DateTime.utc_now(),
            status: :pending
          )
        end

      # Manually check concurrency limit (simulating scheduler behavior)
      job1 = List.first(jobs)
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(job1.rule_id, 1)
      assert {:ok, 1} = ConcurrencyTracker.increment(job1.rule_id)

      # Second job should be blocked
      job2 = Enum.at(jobs, 1)
      assert {:error, :limit_exceeded} = ConcurrencyTracker.check_limit(job2.rule_id, 1)

      # After decrementing, second job should be allowed
      ConcurrencyTracker.decrement(job1.rule_id)
      assert {:ok, :allowed} = ConcurrencyTracker.check_limit(job2.rule_id, 1)
    end

    test "concurrency tracker decrements on job completion", %{rule: rule} do
      # Register a performer
      defmodule TestPerformer do
        def perform(:test_action, _payload) do
          :ok
        end
      end

      TimeOS.register_performer(TestPerformer)

      # Create a job
      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        args: %{"action" => "test_action"}
      }

      job =
        ScheduledJob.changeset(%ScheduledJob{}, job_data)
        |> Repo.insert!()

      # Check initial count
      assert 0 = ConcurrencyTracker.get_count(rule.id)

      # Start worker (this will increment)
      {:ok, _pid} = TimeOS.JobWorker.start_link(job)

      # Wait for job to complete
      Process.sleep(200)

      # Count should be back to 0 after job completes
      assert 0 = ConcurrencyTracker.get_count(rule.id)
    end

    test "concurrency tracker decrements on job timeout", %{rule: rule} do
      # Create a job with timeout
      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        timeout_seconds: 1,
        args: %{"action" => "slow_action"}
      }

      job =
        ScheduledJob.changeset(%ScheduledJob{}, job_data)
        |> Repo.insert!()

      # Check initial count
      assert 0 = ConcurrencyTracker.get_count(rule.id)

      # Start worker (this will increment)
      {:ok, _pid} = TimeOS.JobWorker.start_link(job)

      # Wait for timeout
      Process.sleep(1500)

      # Count should be back to 0 after timeout
      assert 0 = ConcurrencyTracker.get_count(rule.id)
    end
  end
end
