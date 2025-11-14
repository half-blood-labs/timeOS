defmodule TimeOS.JobWorker do
  @moduledoc """
  Executes a scheduled job with retry logic and backoff.
  """

  use GenServer
  require Logger

  alias TimeOS.Schema.ScheduledJob
  alias TimeOS.Repo
  import Ecto.Query

  def start_link(job) do
    GenServer.start_link(__MODULE__, job, name: :"job_worker_#{job.id}")
  end

  @impl true
  def init(job) do
    Process.flag(:trap_exit, true)
    {:ok, job, {:continue, :execute}}
  end

  @impl true
  def handle_continue(:execute, job) do
    execute_job(job)
    {:stop, :normal, job}
  end

  @impl true
  def terminate(reason, job) do
    if reason != :normal and reason != :shutdown do
      Logger.warning("Job worker #{job.id} terminating: #{inspect(reason)}")

      case Repo.get(ScheduledJob, job.id) do
        nil ->
          :ok

        running_job when running_job.status == :running ->
          running_job
          |> Ecto.Changeset.change(%{
            status: :pending,
            last_error: "Worker terminated: #{inspect(reason)}"
          })
          |> Repo.update()

        _ ->
          :ok
      end
    end

    :ok
  end

  defp execute_job(job) do
    Logger.info("Executing job #{job.id}")

    updated_job =
      job
      |> ScheduledJob.mark_running()
      |> Repo.update!()

    TimeOS.Telemetry.emit_event(:job, :started, %{count: 1}, %{job_id: job.id})

    result = execute_action(updated_job.args)

    case result do
      :ok ->
        result_data = %{
          "status" => "success",
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        updated_job
        |> ScheduledJob.mark_success(result_data)
        |> Repo.update!()

        TimeOS.Telemetry.emit_event(:job, :completed, %{count: 1}, %{job_id: job.id})
        Logger.info("Job #{job.id} succeeded")

        trigger_dependent_jobs(updated_job.id)

      {:error, reason} ->
        TimeOS.Telemetry.emit_event(:job, :failed, %{count: 1}, %{job_id: job.id, error: reason})
        handle_retry_or_dead(updated_job, reason)
    end
  end

  defp trigger_dependent_jobs(job_id) do
    query =
      from(j in ScheduledJob,
        where: j.depends_on_job_id == ^job_id and j.status == :pending
      )

    dependent_jobs = Repo.all(query)

    Enum.each(dependent_jobs, fn dependent_job ->
      Logger.info("Job #{dependent_job.id} dependency satisfied, will execute when due")
    end)
  end

  defp execute_action(args) do
    action = Map.get(args, "action")
    opts = Map.get(args, "opts", [])
    payload = Map.get(args, "payload", %{})

    case action do
      nil ->
        {:error, "No action specified"}

      action_name ->
        try do
          call_performer(action_name, payload, opts)
        rescue
          e ->
            {:error, Exception.message(e)}
        end
    end
  end

  defp call_performer(action_name, payload, _opts) do
    action_name = String.to_atom(action_name)
    performers = TimeOS.RuleRegistry.get_performers()

    case Enum.find_value(performers, fn {mod, _} ->
           if function_exported?(mod, :perform, 2) do
             case mod.perform(action_name, payload) do
               :ok -> :ok
               {:error, _} = err -> err
               other -> {:error, "Unexpected response: #{inspect(other)}"}
             end
           end
         end) do
      nil ->
        {:error, "No performer found for action: #{action_name}"}

      result ->
        result
    end
  end

  defp handle_retry_or_dead(job, reason) do
    Logger.warning("Job #{job.id} failed: #{reason}")

    if job.attempt_count >= job.max_attempts do
      job
      |> ScheduledJob.mark_dead_letter(reason)
      |> Repo.update!()

      Logger.error("Job #{job.id} moved to dead letter queue after #{job.attempt_count} attempts")
    else
      backoff_ms = calculate_backoff(job.attempt_count)
      next_perform_at = DateTime.add(DateTime.utc_now(), backoff_ms, :millisecond)

      job
      |> Ecto.Changeset.change(%{
        status: :pending,
        perform_at: next_perform_at,
        last_error: reason
      })
      |> Repo.update!()

      Logger.info("Job #{job.id} scheduled for retry in #{backoff_ms}ms")
    end
  end

  defp calculate_backoff(attempt_count) do
    base = 1_000 * Integer.pow(2, attempt_count)
    jitter = :rand.uniform(1_000)
    base + jitter
  end
end
