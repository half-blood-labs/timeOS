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

    :ok
  end
end
