defmodule Timeos.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
    Supervisor.start_link(children, opts)
  end
end
