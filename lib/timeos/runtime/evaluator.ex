defmodule TimeOS.Evaluator do
  @moduledoc """
  Evaluates events against rules and creates scheduled jobs.
  """

  use GenServer
  require Logger

  alias TimeOS.Schema.ScheduledJob
  alias TimeOS.Repo

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:new_event, event}, state) do
    evaluate_event(event)
    {:noreply, state}
  end

  # Evaluate an event against all rules
  defp evaluate_event(event) do
    rules = TimeOS.RuleRegistry.get_rules()

    Enum.each(rules, fn rule ->
      case match_rule(rule, event) do
        {:ok, jobs} ->
          Enum.each(jobs, &persist_job/1)
          Logger.info("Matched #{length(jobs)} jobs for rule #{rule.name}")

        :no_match ->
          nil
      end
    end)
  end

  # Check if a rule matches an event and generate jobs
  defp match_rule(rule, event) do
    compiled = rule.compiled

    case compiled do
      %{"type" => "on_event", "event_type" => event_type} ->
        if event_type == event.type or event_type == event.type do
          generate_jobs_from_rule(rule, event)
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  # Generate job records from a matched rule
  defp generate_jobs_from_rule(rule, event) do
    compiled = rule.compiled
    offset_ms = Map.get(compiled, "offset_ms", 0)

    perform_at = DateTime.add(event.occurred_at, offset_ms, :millisecond)

    actions = Map.get(compiled, "actions", [])

    jobs = Enum.map(actions, fn action ->
      action_name = get_in(action, ["action"])
      action_opts = get_in(action, ["opts"]) || []

      %{
        rule_id: rule.id,
        event_id: event.id,
        perform_at: perform_at,
        status: :pending,
        max_attempts: 3,
        attempt_count: 0,
        args: %{
          "action" => action_name,
          "opts" => action_opts,
          "event_type" => event.type,
          "payload" => event.payload
        },
        idempotency_key: generate_idempotency_key(rule.id, event.id, action_name)
      }
    end)

    {:ok, jobs}
  end

  defp persist_job(job_data) do
    changeset = ScheduledJob.changeset(%ScheduledJob{}, job_data)

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, job} ->
        Logger.debug("Scheduled job: #{job.id}")

      {:error, reason} ->
        Logger.error("Failed to schedule job: #{inspect(reason)}")
    end
  end

  defp generate_idempotency_key(rule_id, event_id, action_name) do
    :crypto.hash(:sha256, "#{rule_id}#{event_id}#{action_name}")
    |> Base.encode16(case: :lower)
  end
end
