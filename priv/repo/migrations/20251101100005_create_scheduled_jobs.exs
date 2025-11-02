defmodule TimeOS.Repo.Migrations.CreateScheduledJobs do
  use Ecto.Migration

  def change do
    create table(:scheduled_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, :binary_id, null: false
      add :event_id, :binary_id
      add :perform_at, :utc_datetime_usec, null: false
      add :attempt_count, :integer, default: 0
      add :max_attempts, :integer, default: 3
      add :status, :string, default: "pending", null: false
      add :args, :jsonb
      add :last_error, :text
      add :idempotency_key, :string
      timestamps()
    end

    create index(:scheduled_jobs, [:status])
    create index(:scheduled_jobs, [:perform_at])
    create index(:scheduled_jobs, [:rule_id])
    create index(:scheduled_jobs, [:event_id])
    create unique_index(:scheduled_jobs, [:idempotency_key], name: :scheduled_jobs_idempotency_key_unique)
  end
end
