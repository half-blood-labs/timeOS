import Config

config :timeos, TimeOS.Repo,
  database: "timeos_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1
