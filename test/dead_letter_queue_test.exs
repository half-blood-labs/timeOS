defmodule DeadLetterQueueTest do
  use TimeOS.DataCase

  alias TimeOS.Schema.ScheduledJob

  describe "Dead letter queue" do
    test "job moves to dead letter queue after max attempts" do
      job =
        insert(:scheduled_job,
          status: :running,
          attempt_count: 3,
          max_attempts: 3
        )

      updated =
        job
        |> ScheduledJob.mark_dead_letter("Max retries exceeded")
        |> Repo.update!()

      assert updated.status == :dead
      assert updated.dead_letter_queue == true
      assert updated.dead_letter_at != nil
      assert updated.last_error == "Max retries exceeded"
    end

    test "list_dead_letter_jobs returns only dead letter jobs" do
      _normal_job = insert(:scheduled_job, status: :pending, dead_letter_queue: false)
      dlq_job1 = insert(:scheduled_job, status: :dead, dead_letter_queue: true)
      dlq_job2 = insert(:scheduled_job, status: :dead, dead_letter_queue: true)

      jobs = TimeOS.list_dead_letter_jobs()

      assert length(jobs) >= 2
      assert Enum.all?(jobs, &(&1.dead_letter_queue == true))
      assert Enum.any?(jobs, &(&1.id == dlq_job1.id))
      assert Enum.any?(jobs, &(&1.id == dlq_job2.id))
    end

    test "list_dead_letter_jobs filters by rule_id" do
      rule_id = Ecto.UUID.generate()
      other_rule_id = Ecto.UUID.generate()

      _job1 = insert(:scheduled_job, rule_id: rule_id, dead_letter_queue: true)
      _job2 = insert(:scheduled_job, rule_id: rule_id, dead_letter_queue: true)
      _job3 = insert(:scheduled_job, rule_id: other_rule_id, dead_letter_queue: true)

      jobs = TimeOS.list_dead_letter_jobs(rule_id: rule_id)

      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.rule_id == rule_id))
    end

    test "retry_dead_letter_job moves job back to pending" do
      job =
        insert(:scheduled_job,
          status: :dead,
          dead_letter_queue: true,
          attempt_count: 3
        )

      {:ok, retried} = TimeOS.retry_dead_letter_job(job.id)

      assert retried.status == :pending
      assert retried.dead_letter_queue == false
      assert retried.dead_letter_at == nil
      assert retried.attempt_count == 0
    end

    test "retry_dead_letter_job returns error for non-dead-letter job" do
      job = insert(:scheduled_job, status: :pending, dead_letter_queue: false)

      assert {:error, :not_in_dead_letter_queue} = TimeOS.retry_dead_letter_job(job.id)
    end

    test "delete_dead_letter_job permanently deletes job" do
      job = insert(:scheduled_job, status: :dead, dead_letter_queue: true)

      {:ok, _} = TimeOS.delete_dead_letter_job(job.id)

      assert Repo.get(ScheduledJob, job.id) == nil
    end

    test "delete_dead_letter_job returns error for non-dead-letter job" do
      job = insert(:scheduled_job, status: :pending, dead_letter_queue: false)

      assert {:error, :not_in_dead_letter_queue} = TimeOS.delete_dead_letter_job(job.id)
    end
  end
end
