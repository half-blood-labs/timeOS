defmodule TimeOS.Repo.Migrations.AddJobFeatures do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add :priority, :integer, default: 0
      add :timezone, :string
      add :rate_limit_key, :string
      add :dead_letter_queue, :boolean, default: false
      add :dead_letter_at, :utc_datetime_usec
    end

    create index(:scheduled_jobs, [:priority, :perform_at])
    create index(:scheduled_jobs, [:dead_letter_queue])
    create index(:scheduled_jobs, [:rate_limit_key])
  end
end
