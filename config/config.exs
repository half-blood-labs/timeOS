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

import_config "#{Mix.env()}.exs"
