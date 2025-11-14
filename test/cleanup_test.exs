defmodule TimeOS.CleanupTest do
  use TimeOS.DataCase

  alias TimeOS.Cleanup
  alias TimeOS.Schema.{Event, ScheduledJob}

  test "cleanup_old_events removes processed events older than threshold" do
    old_date = DateTime.add(DateTime.utc_now(), -100, :day)
    recent_date = DateTime.add(DateTime.utc_now(), -10, :day)

    insert(:event, type: "test_event", occurred_at: old_date, processed: true)
    insert(:event, type: "test_event", occurred_at: old_date, processed: false)
    insert(:event, type: "test_event", occurred_at: recent_date, processed: true)

    count = Cleanup.cleanup_old_events(90)

    assert count == 1

    remaining = Repo.all(from(e in Event))
    assert length(remaining) == 2
  end

  test "cleanup_old_successful_jobs removes old successful jobs" do
    old_date = DateTime.add(DateTime.utc_now(), -40, :day)
    recent_date = DateTime.add(DateTime.utc_now(), -10, :day)

    insert(:scheduled_job, status: :success, inserted_at: old_date)
    insert(:scheduled_job, status: :success, inserted_at: recent_date)
    insert(:scheduled_job, status: :pending, inserted_at: old_date)

    count = Cleanup.cleanup_old_successful_jobs(30)

    assert count == 1

    remaining = Repo.all(from(j in ScheduledJob, where: j.status == :success))
    assert length(remaining) == 1
  end

  test "cleanup_old_failed_jobs removes old failed jobs" do
    old_date = DateTime.add(DateTime.utc_now(), -10, :day)
    recent_date = DateTime.add(DateTime.utc_now(), -2, :day)

    insert(:scheduled_job, status: :failed, inserted_at: old_date, dead_letter_queue: false)
    insert(:scheduled_job, status: :failed, inserted_at: recent_date, dead_letter_queue: false)
    insert(:scheduled_job, status: :failed, inserted_at: old_date, dead_letter_queue: true)

    count = Cleanup.cleanup_old_failed_jobs(7)

    assert count == 1

    remaining = Repo.all(from(j in ScheduledJob, where: j.status == :failed))
    assert length(remaining) == 2
  end

  test "get_cleanup_stats returns statistics about cleanable data" do
    old_date = DateTime.add(DateTime.utc_now(), -100, :day)

    insert(:event, type: "test_event", occurred_at: old_date, processed: true)
    insert(:scheduled_job, status: :success, inserted_at: old_date)
    insert(:scheduled_job, status: :failed, inserted_at: old_date, dead_letter_queue: false)

    stats = Cleanup.get_cleanup_stats()

    assert stats.old_events >= 1
    assert stats.old_successful_jobs >= 1
    assert stats.old_failed_jobs >= 1
    assert stats.total_cleanable >= 3
  end

  test "cleanup_all runs all cleanup operations" do
    old_date = DateTime.add(DateTime.utc_now(), -100, :day)

    insert(:event, type: "test_event", occurred_at: old_date, processed: true)
    insert(:scheduled_job, status: :success, inserted_at: old_date)
    insert(:scheduled_job, status: :failed, inserted_at: old_date, dead_letter_queue: false)

    result =
      Cleanup.cleanup_all(
        events_retention_days: 90,
        success_jobs_retention_days: 30,
        failed_jobs_retention_days: 7
      )

    assert result.events_deleted >= 1
    assert result.successful_jobs_deleted >= 1
    assert result.failed_jobs_deleted >= 1
    assert result.total_deleted >= 3
  end
end
