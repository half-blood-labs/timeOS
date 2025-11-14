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
    case Process.whereis(TimeOS.Repo) do
      nil ->
        {:ok, _} = Application.ensure_all_started(:timeos)
      _ ->
        :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TimeOS.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TimeOS.Repo, {:shared, self()})
    end

    if Process.whereis(TimeOS.RuleRegistry) do
      Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, Process.whereis(TimeOS.RuleRegistry), self())
    end

    if Process.whereis(TimeOS.Evaluator) do
      Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, Process.whereis(TimeOS.Evaluator), self())
    end

    if Process.whereis(TimeOS.Scheduler) do
      Ecto.Adapters.SQL.Sandbox.allow(TimeOS.Repo, Process.whereis(TimeOS.Scheduler), self())
    end

    :ok
  end
end
