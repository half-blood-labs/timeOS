defmodule TimeOS do
  @moduledoc """
  TimeOS public API for temporal rule engine.
  """

  alias TimeOS.Schema.{Event, ScheduledJob}
  alias TimeOS.Repo
  import Ecto.Query

  @doc """
  Emit a temporal event. Returns event ID.

  Example:
    TimeOS.emit(:user_signup, %{"user_id" => "123"})
  """
  def emit(event_type, payload \\ %{}, opts \\ []) when is_atom(event_type) do
    occurred_at = Keyword.get(opts, :occurred_at, DateTime.utc_now())

    event_changeset = Event.from_emit(event_type, %{
      payload: payload || %{},
      occurred_at: occurred_at
    })

    case Repo.insert(event_changeset) do
      {:ok, event} ->
        # Notify evaluator of new event
        GenServer.cast(TimeOS.Evaluator, {:new_event, event})
        {:ok, event.id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancel a scheduled job by ID.
  """
  def cancel_job(job_id) do
    case Repo.get(ScheduledJob, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        job
        |> ScheduledJob.mark_dead("Cancelled by user")
        |> Repo.update()
    end
  end

  @doc """
  List scheduled jobs with optional filters.

  Filters:
    - event_id: filter by source event
    - rule_id: filter by rule
    - status: :pending, :running, :success, :failed, :dead (default: :pending)
    - limit: default 100
  """
  def list_jobs(filters \\ []) do
    query = ScheduledJob

    # Default to pending unless status is specified
    status = Keyword.get(filters, :status, :pending)

    query =
      if rule_id = Keyword.get(filters, :rule_id) do
        query |> where([j], j.rule_id == ^rule_id)
      else
        query
      end

    query =
      if event_id = Keyword.get(filters, :event_id) do
        query |> where([j], j.event_id == ^event_id)
      else
        query
      end

    query =
      if status do
        query |> where([j], j.status == ^status)
      else
        query
      end

    limit = Keyword.get(filters, :limit, 100)

    query
    |> order_by(desc: :perform_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get a specific job by ID.
  """
  def get_job(job_id) do
    Repo.get(ScheduledJob, job_id)
  end

  @doc """
  Register a custom performer callback.
  """
  def register_performer(mod) when is_atom(mod) do
    GenServer.call(TimeOS.RuleRegistry, {:register_performer, mod})
  end
end
