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

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_next_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    poll_and_execute_due_jobs()
    schedule_next_tick()
    {:noreply, state}
  end

  # Poll database for due jobs and spawn workers
  defp poll_and_execute_due_jobs do
    now = DateTime.utc_now()

    query =
      from(j in ScheduledJob,
        where: j.status == :pending and j.perform_at <= ^now,
        order_by: [asc: :perform_at],
        limit: 50,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    jobs = Repo.all(query)

    Logger.debug("Found #{length(jobs)} due jobs")

    Enum.each(jobs, fn job ->
      spawn_worker(job)
    end)
  end

  # Spawn a worker for a job
  defp spawn_worker(job) do
    case DynamicSupervisor.start_child(
      TimeOS.WorkerSupervisor,
      {TimeOS.JobWorker, job}
    ) do
      {:ok, _pid} ->
        Logger.info("Spawned worker for job #{job.id}")

      {:error, reason} ->
        Logger.error("Failed to spawn worker: #{inspect(reason)}")
    end
  end

  defp schedule_next_tick do
    Process.send_after(self(), :tick, @poll_interval_ms)
  end
end
