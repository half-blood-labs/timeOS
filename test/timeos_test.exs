# test/timeos_test.exs
defmodule TimeOSTest do
  use TimeOS.DataCase

  describe "TimeOS.emit/2" do
    test "emits an event and returns event ID" do
      {:ok, event_id} = TimeOS.emit(:user_signup, %{"user_id" => "123"})

      assert is_binary(event_id)
      assert event = Repo.get(TimeOS.Schema.Event, event_id)
      assert event.type == "user_signup"
      assert event.payload == %{"user_id" => "123"}
    end

    test "emits with custom occurred_at timestamp" do
      ts = ~U[2025-10-31 10:00:00.000000Z]
      {:ok, event_id} = TimeOS.emit(:payment, %{}, occurred_at: ts)

      event = Repo.get(TimeOS.Schema.Event, event_id)
      assert event.occurred_at == ts
    end
  end

  describe "TimeOS.list_jobs/1" do
    test "lists all pending jobs by default" do
      _job1 = insert(:scheduled_job, status: :pending)
      _job2 = insert(:scheduled_job, status: :pending)
      _job3 = insert(:scheduled_job, status: :success)

      jobs = TimeOS.list_jobs()

      assert length(jobs) >= 2
      assert Enum.all?(jobs, &(&1.status == :pending))
    end

    test "filters jobs by status" do
      _job1 = insert(:scheduled_job, status: :success)
      _job2 = insert(:scheduled_job, status: :success)
      _job3 = insert(:scheduled_job, status: :dead)

      jobs = TimeOS.list_jobs(status: :success)

      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.status == :success))
    end

    test "filters jobs by rule_id" do
      rule_id = Ecto.UUID.generate()
      other_rule_id = Ecto.UUID.generate()

      _job1 = insert(:scheduled_job, rule_id: rule_id)
      _job2 = insert(:scheduled_job, rule_id: rule_id)
      _job3 = insert(:scheduled_job, rule_id: other_rule_id)

      jobs = TimeOS.list_jobs(rule_id: rule_id)

      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.rule_id == rule_id))
    end

    test "respects limit parameter" do
      insert_list(10, :scheduled_job)

      jobs = TimeOS.list_jobs(limit: 5)

      assert length(jobs) == 5
    end
  end

  describe "TimeOS.get_job/1" do
    test "gets a job by ID" do
      job = insert(:scheduled_job)

      fetched = TimeOS.get_job(job.id)

      assert fetched.id == job.id
      assert fetched.status == job.status
    end

    test "returns nil for non-existent job" do
      result = TimeOS.get_job(Ecto.UUID.generate())

      assert is_nil(result)
    end
  end

  describe "TimeOS.cancel_job/1" do
    test "marks job as dead" do
      job = insert(:scheduled_job, status: :pending)

      {:ok, cancelled} = TimeOS.cancel_job(job.id)

      assert cancelled.status == :dead
      assert String.contains?(cancelled.last_error || "", ["Cancelled"])
    end

    test "returns error for non-existent job" do
      result = TimeOS.cancel_job(Ecto.UUID.generate())

      assert {:error, :not_found} = result
    end
  end

  describe "Job schemas" do
    test "mark_running updates status and increments attempt count" do
      job = insert(:scheduled_job, status: :pending, attempt_count: 2)

      updated = job
        |> TimeOS.Schema.ScheduledJob.mark_running()
        |> Repo.update!()

      assert updated.status == :running
      assert updated.attempt_count == 3
    end

    test "mark_success sets status to success and clears error" do
      job = insert(:scheduled_job, status: :running, last_error: "Previous error")

      updated = job
        |> TimeOS.Schema.ScheduledJob.mark_success()
        |> Repo.update!()

      assert updated.status == :success
      assert is_nil(updated.last_error)
    end

    test "mark_failed sets status and error message" do
      job = insert(:scheduled_job, status: :running)

      updated =
        job
        |> TimeOS.Schema.ScheduledJob.mark_failed("Database error")
        |> Repo.update!()

      assert updated.status == :failed
      assert updated.last_error == "Database error"
    end

    test "mark_dead sets status and error message" do
      job = insert(:scheduled_job, status: :failed)

      updated =
        job
        |> TimeOS.Schema.ScheduledJob.mark_dead("Max retries exceeded")
        |> Repo.update!()

      assert updated.status == :dead
      assert updated.last_error == "Max retries exceeded"
    end
  end
end
