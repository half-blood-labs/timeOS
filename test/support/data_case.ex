defmodule TimeOS.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring access to the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TimeOS.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TimeOS.DataCase
      import TimeOS.Factory
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TimeOS.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TimeOS.Repo, {:shared, self()})
    end

    allow_gen_servers()

    :ok
  end

  defp allow_gen_servers do
    gen_servers = [
      TimeOS.RuleRegistry,
      TimeOS.Evaluator,
      TimeOS.Scheduler,
      TimeOS.RateLimiter,
      TimeOS.ConcurrencyTracker,
      TimeOS.EventReceiver,
      TimeOS.CleanupScheduler
    ]

    Enum.each(gen_servers, fn module ->
      case Process.whereis(module) do
        nil ->
          :ok

        pid ->
          Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, pid, self())
      end
    end)
  end
end
