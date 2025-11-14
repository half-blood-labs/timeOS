import Config

config :timeos, TimeOS.Repo,
  database: "timeos_dev",
  pool_size: 10,
  log: :info

config :timeos, enable_ui: true
config :timeos, ui_port: 4000
