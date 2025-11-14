defmodule TimeOS.Repo.Migrations.AddCronSupport do
  use Ecto.Migration

  def change do
    alter table(:time_rules) do
      add :cron_expression, :string
      add :priority, :integer, default: 0
      add :rate_limit_per_minute, :integer
      add :timezone, :string
    end

    create index(:time_rules, [:cron_expression])
  end
end
