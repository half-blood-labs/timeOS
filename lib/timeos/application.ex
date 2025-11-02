defmodule Timeos.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
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
      {DynamicSupervisor, strategy: :one_for_one, name: TimeOS.WorkerSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Timeos.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
