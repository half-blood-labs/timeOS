defmodule Timeos.MixProject do
  use Mix.Project

  def project do
    [
      app: :timeos,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_url: "https://github.com/ijunaid8989/timeOS",
        homepage_url: "https://github.com/ijunaid8989/timeOS",
        groups_for_modules: [
          Core: [
            TimeOS,
            TimeOS.DSL.RuleSet
          ],
          Runtime: [
            TimeOS.Evaluator,
            TimeOS.Scheduler,
            TimeOS.JobWorker,
            TimeOS.RuleRegistry,
            TimeOS.EventReceiver,
            TimeOS.RateLimiter
          ],
          Schema: [
            TimeOS.Schema.Event,
            TimeOS.Schema.ScheduledJob,
            TimeOS.Schema.TimeRule
          ],
          Utilities: [
            TimeOS.Health,
            TimeOS.Telemetry,
            TimeOS.Cleanup,
            TimeOS.CronParser,
            TimeOS.TimezoneUtils
          ],
          Web: [
            TimeOS.Web
          ]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Timeos.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:tzdata, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:plug, "~> 1.14", optional: true},
      {:plug_cowboy, "~> 2.6", optional: true},
      {:ex_doc, "~> 0.30", only: :dev},
      {:ex_machina, "~> 2.7", only: :test},
      {:mock, "~> 0.3", only: :test}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "ecto.seed"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
