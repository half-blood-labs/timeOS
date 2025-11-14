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

  @doc """
  Load and register rules from a DSL module.

  Example:
    defmodule MyRules do
      use TimeOS.DSL.RuleSet

      on_event :user_signup, offset: days(2) do
        perform :send_welcome_email
      end
    end

    TimeOS.load_rules_from_module(MyRules)
  """
  def load_rules_from_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__timeos_rules__, 0) do
      rules = module.__timeos_rules__()
      when_clauses = if function_exported?(module, :__timeos_when_clauses__, 0) do
        module.__timeos_when_clauses__()
      else
        List.duplicate(nil, length(rules))
      end
      module_name = inspect(module)

      Enum.zip([rules, when_clauses])
      |> Enum.map(fn {compiled_rule, when_clause} ->
        rule_name = generate_rule_name(compiled_rule, module_name)

        rule_data = %{
          name: rule_name,
          compiled: compiled_rule,
          module: module_name,
          enabled: true,
          cron_expression: Map.get(compiled_rule, "cron_expression"),
          timezone: extract_timezone_from_rule(compiled_rule, module)
        }

        TimeOS.RuleRegistry.add_rule(rule_data, when_clause)
      end)
    else
      {:error, :module_not_found_or_invalid}
    end
  end

  @doc """
  List all registered rules.
  """
  def list_rules do
    TimeOS.RuleRegistry.get_rules()
  end

  @doc """
  Get a rule by ID.
  """
  def get_rule(rule_id) do
    rules = TimeOS.RuleRegistry.get_rules()
    Enum.find(rules, &(&1.id == rule_id))
  end

  @doc """
  Enable or disable a rule.
  """
  def enable_rule(rule_id, enabled \\ true) do
    TimeOS.RuleRegistry.update_rule(rule_id, %{enabled: enabled})
  end

  @doc """
  Update a rule.
  """
  def update_rule(rule_id, updates) do
    TimeOS.RuleRegistry.update_rule(rule_id, updates)
  end

  @doc """
  Delete a rule.
  """
  def delete_rule(rule_id) do
    TimeOS.RuleRegistry.delete_rule(rule_id)
  end

  @doc """
  Reload rules from database.
  """
  def reload_rules do
    TimeOS.RuleRegistry.reload_rules()
  end

  @doc """
  List jobs in dead letter queue.
  """
  def list_dead_letter_jobs(filters \\ []) do
    query = from(j in ScheduledJob,
      where: j.dead_letter_queue == true,
      order_by: [desc: :dead_letter_at]
    )

    query = if rule_id = Keyword.get(filters, :rule_id) do
      query |> where([j], j.rule_id == ^rule_id)
    else
      query
    end

    limit = Keyword.get(filters, :limit, 100)
    query |> limit(^limit) |> Repo.all()
  end

  @doc """
  Retry a dead letter job.
  """
  def retry_dead_letter_job(job_id) do
    case Repo.get(ScheduledJob, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        if job.dead_letter_queue do
          job
          |> Ecto.Changeset.change(%{
            status: :pending,
            dead_letter_queue: false,
            dead_letter_at: nil,
            attempt_count: 0
          })
          |> Repo.update()
        else
          {:error, :not_in_dead_letter_queue}
        end
    end
  end

  @doc """
  Delete a dead letter job permanently.
  """
  def delete_dead_letter_job(job_id) do
    case Repo.get(ScheduledJob, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        if job.dead_letter_queue do
          Repo.delete(job)
        else
          {:error, :not_in_dead_letter_queue}
        end
    end
  end

  defp extract_timezone_from_rule(compiled_rule, module) do
    if function_exported?(module, :__timeos_rule_opts__, 0) do
      opts = module.__timeos_rule_opts__()
      Keyword.get(opts, :timezone)
    else
      Map.get(compiled_rule, "timezone")
    end
  end

  defp generate_rule_name(compiled_rule, module_name) do
    case compiled_rule do
      %{"type" => "on_event", "event_type" => event_type} ->
        "#{module_name}.on_event.#{event_type}"

      %{"type" => "every", "interval_ms" => interval_ms} ->
        "#{module_name}.every.#{interval_ms}ms"

      %{"type" => "cron", "cron_expression" => cron_expr} ->
        "#{module_name}.cron.#{String.replace(cron_expr, " ", "_")}"

      _ ->
        "#{module_name}.rule_#{:erlang.phash2(compiled_rule)}"
    end
  end
end
