import Config

config :timeos,
  ecto_repos: [TimeOS.Repo],
  repo: TimeOS.Repo

config :timeos, TimeOS.Repo,
  database: "timeos_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 10

config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :job_id, :event_id, :rule_id]

import_config "#{Mix.env()}.exs"
