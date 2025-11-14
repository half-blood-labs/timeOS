defmodule TimeOS.Cleanup do
  @moduledoc """
  Utilities for cleaning up old events and jobs to prevent database bloat.
  """

  alias TimeOS.Repo
  alias TimeOS.Schema.{Event, ScheduledJob}
  import Ecto.Query
  require Logger

  @doc """
  Clean up old events older than the specified days.
  Returns count of deleted events.
  """
  def cleanup_old_events(days_old \\ 90) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_old, :day)

    query =
      from(e in Event,
        where: e.occurred_at < ^cutoff_date and e.processed == true
      )

    {count, _} = Repo.delete_all(query)
    Logger.info("Cleaned up #{count} old events older than #{days_old} days")
    count
  end

  @doc """
  Clean up old successful jobs older than the specified days.
  Returns count of deleted jobs.
  """
  def cleanup_old_successful_jobs(days_old \\ 30) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_old, :day)

    query =
      from(j in ScheduledJob,
        where: j.status == :success and j.inserted_at < ^cutoff_date
      )

    {count, _} = Repo.delete_all(query)
    Logger.info("Cleaned up #{count} old successful jobs older than #{days_old} days")
    count
  end

  @doc """
  Clean up old failed jobs (not in dead letter queue) older than the specified days.
  Returns count of deleted jobs.
  """
  def cleanup_old_failed_jobs(days_old \\ 7) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_old, :day)

    query =
      from(j in ScheduledJob,
        where:
          j.status == :failed and
            j.dead_letter_queue == false and
            j.inserted_at < ^cutoff_date
      )

    {count, _} = Repo.delete_all(query)
    Logger.info("Cleaned up #{count} old failed jobs older than #{days_old} days")
    count
  end

  @doc """
  Archive old events to a separate table or mark them for archival.
  This is a placeholder - implement actual archival logic as needed.
  """
  def archive_old_events(days_old \\ 365) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_old, :day)

    query =
      from(e in Event,
        where: e.occurred_at < ^cutoff_date and e.processed == true
      )

    events = Repo.all(query)
    Logger.info("Found #{length(events)} events to archive (older than #{days_old} days)")
    length(events)
  end

  @doc """
  Clean up all old data based on configured retention periods.
  This is a convenience function that runs all cleanup operations.
  """
  def cleanup_all(opts \\ []) do
    events_days = Keyword.get(opts, :events_retention_days, 90)
    success_jobs_days = Keyword.get(opts, :success_jobs_retention_days, 30)
    failed_jobs_days = Keyword.get(opts, :failed_jobs_retention_days, 7)

    Logger.info("Starting database cleanup...")

    events_count = cleanup_old_events(events_days)
    success_count = cleanup_old_successful_jobs(success_jobs_days)
    failed_count = cleanup_old_failed_jobs(failed_jobs_days)

    total = events_count + success_count + failed_count
    Logger.info("Cleanup complete: removed #{total} total records")

    %{
      events_deleted: events_count,
      successful_jobs_deleted: success_count,
      failed_jobs_deleted: failed_count,
      total_deleted: total
    }
  end

  @doc """
  Get statistics about old data that could be cleaned up.
  """
  def get_cleanup_stats do
    now = DateTime.utc_now()

    old_events_count =
      from(e in Event,
        where: e.occurred_at < ^DateTime.add(now, -90, :day) and e.processed == true
      )
      |> Repo.aggregate(:count, :id)

    old_success_jobs_count =
      from(j in ScheduledJob,
        where: j.status == :success and j.inserted_at < ^DateTime.add(now, -30, :day)
      )
      |> Repo.aggregate(:count, :id)

    old_failed_jobs_count =
      from(j in ScheduledJob,
        where:
          j.status == :failed and
            j.dead_letter_queue == false and
            j.inserted_at < ^DateTime.add(now, -7, :day)
      )
      |> Repo.aggregate(:count, :id)

    %{
      old_events: old_events_count,
      old_successful_jobs: old_success_jobs_count,
      old_failed_jobs: old_failed_jobs_count,
      total_cleanable: old_events_count + old_success_jobs_count + old_failed_jobs_count
    }
  end
end
