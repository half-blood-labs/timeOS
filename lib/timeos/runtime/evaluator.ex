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

  defp evaluate_event(event) do
    rules = TimeOS.RuleRegistry.get_rules()

    Enum.each(rules, fn rule ->
      case match_rule(rule, event) do
        {:ok, jobs} ->
          Enum.each(jobs, &persist_job/1)
          TimeOS.Telemetry.emit_event(:rule, :matched, %{job_count: length(jobs)}, %{rule_id: rule.id, event_id: event.id})
          Logger.info("Matched #{length(jobs)} jobs for rule #{rule.name}")

        :no_match ->
          nil
      end
    end)
  end

  defp match_rule(rule, event) do
    compiled = rule.compiled

    case compiled do
      %{"type" => "on_event", "event_type" => event_type} ->
        event_type_str = normalize_event_type(event_type)
        event_type_normalized = normalize_event_type(event.type)

        if event_type_str == event_type_normalized do
          if evaluate_when_clause(rule, compiled, event) do
            generate_jobs_from_rule(rule, event)
          else
            :no_match
          end
        else
          :no_match
        end

      %{"type" => "every"} ->
        :no_match

      %{"type" => "cron"} ->
        :no_match

      _ ->
        :no_match
    end
  end

  defp normalize_event_type(event_type) when is_atom(event_type), do: Atom.to_string(event_type)
  defp normalize_event_type(event_type) when is_binary(event_type), do: event_type
  defp normalize_event_type(_), do: ""

  defp evaluate_when_clause(rule, compiled, event) do
    if Map.get(compiled, "when_present", false) do
      case TimeOS.RuleRegistry.get_when_clause(rule.id) do
        nil -> true
        when_pred when is_function(when_pred, 1) -> when_pred.(event.payload)
        when_pred when is_function(when_pred, 2) -> when_pred.(event.payload, event)
        _ -> true
      end
    else
      true
    end
  end

  defp generate_jobs_from_rule(rule, event) do
    compiled = rule.compiled
    offset_ms = Map.get(compiled, "offset_ms", 0) || 0

    perform_at = calculate_perform_at(event.occurred_at, offset_ms, rule.timezone)

    actions = Map.get(compiled, "actions", [])

    jobs = Enum.map(actions, fn action ->
      {action_name, action_opts} = extract_action_info(action)

      rate_limit_key = generate_rate_limit_key(rule, action_name)
      depends_on_job_id = if is_map(action_opts), do: Map.get(action_opts, "depends_on_job_id"), else: nil

      %{
        rule_id: rule.id,
        event_id: event.id,
        perform_at: perform_at,
        status: :pending,
        max_attempts: 3,
        attempt_count: 0,
        priority: rule.priority || 0,
        timezone: rule.timezone,
        rate_limit_key: rate_limit_key,
        depends_on_job_id: depends_on_job_id,
        args: %{
          "action" => normalize_action_name(action_name),
          "opts" => action_opts || [],
          "event_type" => event.type,
          "payload" => event.payload
        },
        idempotency_key: generate_idempotency_key(rule.id, event.id, action_name)
      }
    end)

    {:ok, jobs}
  end

  defp calculate_perform_at(occurred_at, offset_ms, nil) do
    DateTime.add(occurred_at, offset_ms, :millisecond)
  end

  defp calculate_perform_at(occurred_at, offset_ms, timezone) do
    case TimeOS.TimezoneUtils.to_timezone(occurred_at, timezone) do
      {:ok, dt} ->
        dt
        |> DateTime.add(offset_ms, :millisecond)
        |> TimeOS.TimezoneUtils.to_utc()
        |> elem(1)

      _ ->
        DateTime.add(occurred_at, offset_ms, :millisecond)
    end
  end

  defp extract_action_info(%{"action" => action, "opts" => opts}), do: {action, opts}
  defp extract_action_info(%{"action" => action}), do: {action, []}
  defp extract_action_info({:perform, action, opts}) when is_list(opts), do: {action, opts}
  defp extract_action_info({:perform, action}), do: {action, []}
  defp extract_action_info(action) when is_atom(action), do: {action, []}
  defp extract_action_info(action) when is_binary(action), do: {action, []}
  defp extract_action_info(_), do: {nil, []}

  defp normalize_action_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_action_name(name) when is_binary(name), do: name
  defp normalize_action_name(_), do: ""

  defp generate_rate_limit_key(rule, action_name) do
    if rule.rate_limit_per_minute do
      "rule:#{rule.id}:action:#{normalize_action_name(action_name)}"
    else
      nil
    end
  end

  defp persist_job(job_data) do
    changeset = ScheduledJob.changeset(%ScheduledJob{}, job_data)

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, job} ->
        TimeOS.Telemetry.emit_event(:job, :created, %{count: 1}, %{job_id: job.id, rule_id: job.rule_id})
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
