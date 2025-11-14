defmodule Timeos.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    TimeOS.Telemetry.setup()

    children = [
      TimeOS.Repo,
      TimeOS.RuleRegistry,
      TimeOS.EventReceiver,
      TimeOS.Evaluator,
      TimeOS.Scheduler,
      TimeOS.RateLimiter,
      {DynamicSupervisor, strategy: :one_for_one, name: TimeOS.WorkerSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Timeos.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    if Application.get_env(:timeos, :enable_ui, false) do
      start_ui()
    end

    {:ok, pid}
  end

  @impl true
  def stop(_state) do
    require Logger
    Logger.info("Shutting down TimeOS...")
    wait_for_running_jobs()
    :ok
  end

  defp wait_for_running_jobs do
    require Logger
    running_count = TimeOS.Health.check().metrics.running_jobs

    if running_count > 0 do
      Logger.info("Waiting for #{running_count} running jobs to complete...")
      Process.sleep(5_000)

      remaining = TimeOS.Health.check().metrics.running_jobs
      if remaining > 0 do
        Logger.warning("#{remaining} jobs still running after grace period")
      end
    end
  end

  defp start_ui do
    require Logger
    case Application.ensure_all_started(:plug_cowboy) do
      {:ok, _} ->
        TimeOS.Web.start()
      _ ->
        Logger.warning("Plug/Cowboy not available, UI not started")
    end
  end
end
