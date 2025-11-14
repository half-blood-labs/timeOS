defmodule TimeOS.CleanupScheduler do
  @moduledoc """
  Periodically runs cleanup tasks to prevent database bloat.
  """

  use GenServer
  require Logger

  @default_cleanup_interval_ms 24 * 60 * 60 * 1000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("Running scheduled database cleanup...")

    retention_opts = [
      events_retention_days: Application.get_env(:timeos, :events_retention_days, 90),
      success_jobs_retention_days: Application.get_env(:timeos, :success_jobs_retention_days, 30),
      failed_jobs_retention_days: Application.get_env(:timeos, :failed_jobs_retention_days, 7)
    ]

    TimeOS.Cleanup.cleanup_all(retention_opts)

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    interval_ms = Application.get_env(:timeos, :cleanup_interval_ms, @default_cleanup_interval_ms)
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
