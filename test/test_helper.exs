ExUnit.start()

{:ok, _} = Application.ensure_all_started(:ex_machina)

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)

Ecto.Adapters.SQL.Sandbox.mode(TimeOS.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:timeos)
