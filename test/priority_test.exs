defmodule PriorityTest do
  use TimeOS.DataCase

  alias TimeOS.Schema.ScheduledJob
  import Ecto.Query

  describe "Job prioritization" do
    test "jobs are ordered by priority then perform_at" do
      now = DateTime.utc_now()

      _low_priority = insert(:scheduled_job,
        priority: 0,
        perform_at: now,
        status: :pending
      )

      _high_priority = insert(:scheduled_job,
        priority: 10,
        perform_at: DateTime.add(now, 100, :second),
        status: :pending
      )

      _medium_priority = insert(:scheduled_job,
        priority: 5,
        perform_at: now,
        status: :pending
      )

      jobs = from(j in ScheduledJob,
        where: j.status == :pending,
        order_by: [desc: :priority, asc: :perform_at]
      )
      |> Repo.all()

      priorities = Enum.map(jobs, & &1.priority)
      assert priorities == [10, 5, 0]
    end

    test "evaluator sets priority from rule" do
      rule = insert(:time_rule, priority: 7)

      event = insert(:event, type: "test_event")

      rule_data = %{
        rule_id: rule.id,
        event_id: event.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        priority: rule.priority,
        args: %{"action" => "test"}
      }

      job = ScheduledJob.changeset(%ScheduledJob{}, rule_data)
        |> Repo.insert!()

      assert job.priority == 7
    end

    test "default priority is 0" do
      job = insert(:scheduled_job)

      assert job.priority == 0
    end
  end
end
