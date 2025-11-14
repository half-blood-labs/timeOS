import Config

config :timeos, TimeOS.Repo,
  database: "timeos_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :logger,
  level: :warn,
  compile_time_purge_matching: [
    [level_lower_than: :warn]
  ]
