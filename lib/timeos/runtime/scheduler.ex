defmodule TimeOS.Scheduler do
  @moduledoc """
  Polls for due scheduled jobs and spawns workers.
  """

  use GenServer
  require Logger

  alias TimeOS.Schema.ScheduledJob
  alias TimeOS.Repo
  import Ecto.Query

  @poll_interval_ms 1_000
  @every_rules_check_interval_ms 1_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_next_tick()
    schedule_every_rules_check()
    schedule_cron_rules_check()
    {:ok, %{last_every_check: DateTime.utc_now(), last_cron_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:tick, state) do
    poll_and_execute_due_jobs()
    schedule_next_tick()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_every_rules, state) do
    check_and_schedule_every_rules()
    schedule_every_rules_check()
    {:noreply, %{state | last_every_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:check_cron_rules, state) do
    check_and_schedule_cron_rules()
    schedule_cron_rules_check()
    {:noreply, %{state | last_cron_check: DateTime.utc_now()}}
  end

  defp poll_and_execute_due_jobs do
    now = DateTime.utc_now()

    query =
      from(j in ScheduledJob,
        where: j.status == :pending and j.perform_at <= ^now and j.dead_letter_queue == false,
        order_by: [desc: :priority, asc: :perform_at],
        limit: 50,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    jobs =
      try do
        Repo.all(query)
      rescue
        DBConnection.OwnershipError ->
          Logger.warning("Database ownership error in Scheduler, skipping poll")
          []

        e ->
          Logger.error("Error polling jobs: #{inspect(e)}")
          []
      catch
        :exit, _ ->
          Logger.warning("Exit while polling jobs")
          []
      end

    Logger.debug("Found #{length(jobs)} due jobs")

    Enum.each(jobs, fn job ->
      if can_execute_job?(job) do
        if check_rate_limit(job) do
          if check_concurrency_limit(job) do
            # Mark as running immediately to prevent duplicate execution
            case job
                 |> ScheduledJob.mark_running()
                 |> Repo.update() do
              {:ok, updated_job} ->
                spawn_worker(updated_job)

              {:error, _reason} ->
                Logger.warning("Failed to mark job #{job.id} as running, skipping")
            end
          else
            Logger.debug("Job #{job.id} concurrency limited, deferring")
          end
        else
          Logger.debug("Job #{job.id} rate limited, deferring")
        end
      else
        Logger.debug("Job #{job.id} waiting for dependency")
      end
    end)
  end

  defp can_execute_job?(job) do
    if job.depends_on_job_id do
      try do
        case Repo.get(ScheduledJob, job.depends_on_job_id) do
          nil -> false
          dependent_job -> dependent_job.status == :success
        end
      rescue
        DBConnection.OwnershipError ->
          Logger.warning("Database ownership error checking job dependency")
          false

        _ ->
          false
      catch
        :exit, _ ->
          false
      end
    else
      true
    end
  end

  defp check_rate_limit(job) do
    if job.rate_limit_key do
      rule = TimeOS.RuleRegistry.get_rule_by_id(job.rule_id)

      if rule && rule.rate_limit_per_minute do
        case TimeOS.RateLimiter.check_rate_limit(job.rate_limit_key, rule.rate_limit_per_minute) do
          {:ok, :allowed} ->
            true

          {:error, :rate_limited, wait_seconds} ->
            TimeOS.Telemetry.emit_event(
              :rate_limit,
              :exceeded,
              %{count: 1, wait_seconds: wait_seconds},
              %{job_id: job.id}
            )

            Logger.debug("Job #{job.id} rate limited, waiting #{wait_seconds}s")
            false

          _ ->
            true
        end
      else
        true
      end
    else
      true
    end
  end

  defp check_concurrency_limit(job) do
    if job.rule_id do
      rule = TimeOS.RuleRegistry.get_rule_by_id(job.rule_id)

      if rule && rule.concurrency_limit do
        case TimeOS.ConcurrencyTracker.check_limit(job.rule_id, rule.concurrency_limit) do
          {:ok, :allowed} ->
            true

          {:error, :limit_exceeded} ->
            TimeOS.Telemetry.emit_event(
              :concurrency_limit,
              :exceeded,
              %{count: 1},
              %{job_id: job.id, rule_id: job.rule_id}
            )

            Logger.debug("Job #{job.id} concurrency limited for rule #{job.rule_id}")
            false

          _ ->
            true
        end
      else
        true
      end
    else
      true
    end
  end

  defp spawn_worker(job) do
    case DynamicSupervisor.start_child(
           TimeOS.WorkerSupervisor,
           {TimeOS.JobWorker, job}
         ) do
      {:ok, _pid} ->
        TimeOS.Telemetry.emit_event(:job, :started, %{count: 1}, %{job_id: job.id})
        Logger.info("Spawned worker for job #{job.id}")

      {:error, reason} ->
        Logger.error("Failed to spawn worker: #{inspect(reason)}")
    end
  end

  defp schedule_next_tick do
    Process.send_after(self(), :tick, @poll_interval_ms)
  end

  defp schedule_every_rules_check do
    Process.send_after(self(), :check_every_rules, @every_rules_check_interval_ms)
  end

  defp schedule_cron_rules_check do
    Process.send_after(self(), :check_cron_rules, 60_000)
  end

  defp check_and_schedule_every_rules do
    rules = TimeOS.RuleRegistry.get_rules()
    now = DateTime.utc_now()

    every_rules =
      Enum.filter(rules, fn rule ->
        compiled = rule.compiled
        Map.get(compiled, "type") == "every" and rule.enabled
      end)

    Enum.each(every_rules, fn rule ->
      schedule_every_rule_jobs(rule, now)
    end)
  end

  defp check_and_schedule_cron_rules do
    rules = TimeOS.RuleRegistry.get_rules()
    now = DateTime.utc_now()

    cron_rules =
      Enum.filter(rules, fn rule ->
        rule.cron_expression && rule.enabled
      end)

    Enum.each(cron_rules, fn rule ->
      schedule_cron_rule_jobs(rule, now)
    end)
  end

  defp schedule_every_rule_jobs(rule, now) do
    compiled = rule.compiled
    interval_ms = Map.get(compiled, "interval_ms", 0)
    actions = Map.get(compiled, "actions", [])

    # Check if there's already a pending job for this rule
    pending_job_query =
      from(j in ScheduledJob,
        where: j.rule_id == ^rule.id and j.status == :pending,
        limit: 1
      )

    pending_job = Repo.one(pending_job_query)

    # Don't create if there's already a pending job
    if pending_job do
      :ok
    else
      query =
        from(j in ScheduledJob,
          where: j.rule_id == ^rule.id,
          order_by: [desc: :perform_at],
          limit: 1
        )

      last_job = Repo.one(query)

      should_create =
        case last_job do
          nil ->
            true

          job ->
            DateTime.diff(now, job.perform_at, :millisecond) >= interval_ms
        end

      if should_create do
        base_time =
          case last_job do
            nil -> now
            job -> job.perform_at
          end

        # Calculate how many intervals have passed and create jobs for all of them
        # This ensures we don't miss jobs when the check interval is longer than the job interval
        elapsed_ms = DateTime.diff(now, base_time, :millisecond)
        intervals_to_create = div(elapsed_ms, interval_ms)

        # Create jobs for each missed interval (up to a reasonable limit to prevent spam)
        jobs_to_create = min(intervals_to_create, 100)

        Enum.each(0..(jobs_to_create - 1), fn interval_offset ->
          next_perform_at = calculate_next_interval(base_time, interval_ms, interval_offset)
          next_perform_at = apply_timezone(next_perform_at, rule.timezone)

          Enum.each(actions, fn action ->
            {action_name, action_opts} = extract_action_info(action)

            rate_limit_key = generate_rate_limit_key(rule, action_name)

            job_data = %{
              rule_id: rule.id,
              event_id: nil,
              perform_at: next_perform_at,
              status: :pending,
              max_attempts: 3,
              attempt_count: 0,
              priority: rule.priority || 0,
              timezone: rule.timezone,
              rate_limit_key: rate_limit_key,
              args: %{
                "action" => normalize_action_name(action_name),
                "opts" => action_opts || [],
                "event_type" => nil,
                "payload" => %{}
              },
              idempotency_key:
                generate_idempotency_key(rule.id, nil, action_name, next_perform_at)
            }

            changeset = ScheduledJob.changeset(%ScheduledJob{}, job_data)

            case Repo.insert(changeset, on_conflict: :nothing) do
              {:ok, _job} ->
                Logger.debug("Scheduled every rule job for rule #{rule.name}")

              {:error, reason} ->
                Logger.error("Failed to schedule every rule job: #{inspect(reason)}")
            end
          end)
        end)
      end
    end
  end

  defp schedule_cron_rule_jobs(rule, now) do
    case TimeOS.CronParser.next_execution_time(rule.cron_expression, now) do
      {:ok, next_time} ->
        next_time = apply_timezone(next_time, rule.timezone)

        query =
          from(j in ScheduledJob,
            where: j.rule_id == ^rule.id and j.status == :pending,
            order_by: [desc: :perform_at],
            limit: 1
          )

        existing_job = Repo.one(query)

        if !existing_job || DateTime.compare(existing_job.perform_at, next_time) != :eq do
          compiled = rule.compiled
          actions = Map.get(compiled, "actions", [])

          Enum.each(actions, fn action ->
            {action_name, action_opts} = extract_action_info(action)

            rate_limit_key = generate_rate_limit_key(rule, action_name)

            job_data = %{
              rule_id: rule.id,
              event_id: nil,
              perform_at: next_time,
              status: :pending,
              max_attempts: 3,
              attempt_count: 0,
              priority: rule.priority || 0,
              timezone: rule.timezone,
              rate_limit_key: rate_limit_key,
              args: %{
                "action" => normalize_action_name(action_name),
                "opts" => action_opts || [],
                "event_type" => nil,
                "payload" => %{}
              },
              idempotency_key: generate_idempotency_key(rule.id, nil, action_name, next_time)
            }

            changeset = ScheduledJob.changeset(%ScheduledJob{}, job_data)

            case Repo.insert(changeset, on_conflict: :nothing) do
              {:ok, _job} ->
                Logger.debug("Scheduled cron rule job for rule #{rule.name}")

              {:error, reason} ->
                Logger.error("Failed to schedule cron rule job: #{inspect(reason)}")
            end
          end)
        end

      {:error, reason} ->
        Logger.error("Failed to parse cron expression for rule #{rule.name}: #{inspect(reason)}")
    end
  end

  defp apply_timezone(datetime, nil), do: datetime

  defp apply_timezone(datetime, timezone) do
    case TimeOS.TimezoneUtils.to_timezone(datetime, timezone) do
      {:ok, dt} -> TimeOS.TimezoneUtils.to_utc(dt) |> elem(1)
      _ -> datetime
    end
  end

  defp calculate_next_interval(base_time, interval_ms, offset) do
    base_ms = DateTime.to_unix(base_time, :millisecond)

    # Add (offset + 1) intervals to the base time
    # offset=0 means the next interval, offset=1 means the one after that, etc.
    next_ms = base_ms + (offset + 1) * interval_ms
    DateTime.from_unix!(next_ms, :millisecond)
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

  defp generate_idempotency_key(rule_id, event_id, action_name, perform_at) do
    key = "#{rule_id}#{event_id || "every"}#{action_name}#{DateTime.to_iso8601(perform_at)}"

    :crypto.hash(:sha256, key)
    |> Base.encode16(case: :lower)
  end
end
