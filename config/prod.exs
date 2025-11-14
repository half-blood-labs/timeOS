import Config

config :timeos, TimeOS.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "20")),
  timeout: String.to_integer(System.get_env("DB_TIMEOUT", "15000")),
  ssl: System.get_env("DB_SSL", "false") == "true"

database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """

config :timeos, TimeOS.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "20"))

config :timeos,
  enable_ui: System.get_env("ENABLE_UI", "false") == "true",
  ui_port: String.to_integer(System.get_env("UI_PORT", "4000"))

config :logger,
  level: String.to_atom(System.get_env("LOG_LEVEL", "info")),
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :job_id, :event_id, :rule_id]
