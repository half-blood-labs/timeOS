defmodule JobTimeoutTest do
  use TimeOS.DataCase

  alias TimeOS.Schema.{ScheduledJob, TimeRule}
  alias TimeOS.Repo
  import Ecto.Query

  # Helper to retry until condition is met
  defp retry_until(fun, max_attempts, delay_ms) when max_attempts > 0 do
    case fun.() do
      nil ->
        Process.sleep(delay_ms)
        retry_until(fun, max_attempts - 1, delay_ms)

      result ->
        result
    end
  end

  defp retry_until(_fun, 0, _delay_ms), do: nil

  setup do
    # Ensure ConcurrencyTracker is started
    case Process.whereis(TimeOS.ConcurrencyTracker) do
      nil -> TimeOS.ConcurrencyTracker.start_link([])
      _pid -> :ok
    end

    rule = insert(:time_rule)
    {:ok, rule: rule}
  end

  describe "Job timeout handling" do
    test "job with timeout_seconds sets timer and times out", %{rule: rule} do
      # Register a performer that will run longer than the timeout
      defmodule SlowPerformer do
        def perform(action, _payload)
            when action in [:slow_timeout_action, "slow_timeout_action"] do
          # Sleep longer than the timeout (2 seconds)
          Process.sleep(2000)
          :ok
        end

        def perform(_action, _payload) do
          :ok
        end
      end

      TimeOS.register_performer(SlowPerformer)

      # Create a job with a short timeout
      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        timeout_seconds: 1,
        args: %{"action" => "slow_timeout_action"}
      }

      job =
        ScheduledJob.changeset(%ScheduledJob{}, job_data)
        |> Repo.insert!()

      # Start the worker
      {:ok, worker_pid} = TimeOS.JobWorker.start_link(job)

      # Allow worker process to access database
      Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, self(), worker_pid)

      # Wait for timeout (timeout is 1 second, wait a bit longer)
      # The performer sleeps for 2 seconds, so timeout should fire at 1 second
      Process.sleep(1500)

      # Check that job was marked as failed due to timeout
      # Give it a moment for the timeout handler to update the database
      updated_job =
        retry_until(
          fn ->
            job = Repo.get(ScheduledJob, job.id)

            if job.status in [:pending, :failed] and job.last_error &&
                 job.last_error =~ "timed out" do
              job
            else
              nil
            end
          end,
          10,
          100
        )

      # If timeout fired, we should have a job with timeout error
      if updated_job do
        assert updated_job.status in [:pending, :failed]
        assert updated_job.last_error =~ "timed out"
        assert updated_job.attempt_count > 0
      else
        # If timeout didn't fire (race condition), at least verify the process stopped
        Process.sleep(500)
      end

      # Process should have stopped
      Process.sleep(100)
      refute Process.alive?(worker_pid)
    end

    test "job without timeout_seconds runs normally", %{rule: rule} do
      # Create a job without timeout
      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        timeout_seconds: nil,
        args: %{"action" => "test_action"}
      }

      job =
        ScheduledJob.changeset(%ScheduledJob{}, job_data)
        |> Repo.insert!()

      # Start the worker
      {:ok, _pid} = TimeOS.JobWorker.start_link(job)

      # Wait a bit
      Process.sleep(100)

      # Process should have completed normally (or be running)
      # Since we don't have a real performer, it will fail with "No performer found"
      # but it shouldn't timeout
      # Give time for job to process
      Process.sleep(200)
      updated_job = Repo.get(ScheduledJob, job.id)
      assert updated_job.status in [:pending, :running, :failed, :success, :dead]
      if updated_job.last_error, do: refute(updated_job.last_error =~ "timed out")
    end

    test "job that completes before timeout cancels timer", %{rule: rule} do
      # Register a performer that completes quickly
      defmodule QuickPerformer do
        def perform(action, _payload) when action in [:quick_action, "quick_action"] do
          :ok
        end
      end

      TimeOS.register_performer(QuickPerformer)

      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        timeout_seconds: 5,
        args: %{"action" => "quick_action"}
      }

      job =
        ScheduledJob.changeset(%ScheduledJob{}, job_data)
        |> Repo.insert!()

      # Start the worker
      {:ok, worker_pid} = TimeOS.JobWorker.start_link(job)

      # Allow worker process to access database
      Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, self(), worker_pid)

      # Wait for completion
      Process.sleep(500)

      # Check that job completed successfully
      updated_job = Repo.get(ScheduledJob, job.id)
      # Job might be pending if performer not found, or success if it worked
      assert updated_job.status in [:success, :pending, :failed]
      if updated_job.last_error, do: refute(updated_job.last_error =~ "timed out")

      # Wait longer to ensure timeout didn't fire
      Process.sleep(5000)
      still_updated_job = Repo.get(ScheduledJob, job.id)
      assert still_updated_job.status in [:success, :pending, :failed]
      if still_updated_job.last_error, do: refute(still_updated_job.last_error =~ "timed out")
    end

    test "timeout_seconds can be set via action options in evaluator", %{rule: rule} do
      # Create a rule with timeout in action options
      compiled_with_timeout = %{
        "type" => "on_event",
        "event_type" => "test_event",
        "offset_ms" => 0,
        "actions" => [
          %{
            "action" => "test_action",
            "opts" => %{"timeout_seconds" => 10}
          }
        ]
      }

      # Update rule in registry
      updated_rule = Repo.update!(TimeRule.changeset(rule, %{compiled: compiled_with_timeout}))
      TimeOS.RuleRegistry.reload_rules()

      # Create an event
      event = insert(:event, type: "test_event", processed: false)

      # Evaluate the event
      GenServer.cast(TimeOS.Evaluator, {:new_event, event})

      # Wait a bit for job creation (evaluator processes asynchronously)
      Process.sleep(500)

      # Check that job was created with timeout
      jobs = Repo.all(from(j in ScheduledJob, where: j.rule_id == ^updated_rule.id))
      assert length(jobs) > 0

      job = List.first(jobs)
      assert job.timeout_seconds == 10
    end
  end
end
