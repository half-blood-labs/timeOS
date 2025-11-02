defmodule TimeOS.Repo do
  use Ecto.Repo,
    otp_app: :timeos,
    adapter: Ecto.Adapters.Postgres
end
