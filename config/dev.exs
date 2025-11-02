import Config

config :timeos, TimeOS.Repo,
  database: "timeos_dev",
  pool_size: 10,
  log: :info
