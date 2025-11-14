defmodule TimeOS.Repo.Migrations.AddJobDependencies do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add :depends_on_job_id, :binary_id
      add :result, :jsonb
    end

    create index(:scheduled_jobs, [:depends_on_job_id])
  end
end
