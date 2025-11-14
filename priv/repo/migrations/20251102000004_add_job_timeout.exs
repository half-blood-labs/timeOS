defmodule TimeOS.Repo.Migrations.AddJobTimeout do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add :timeout_seconds, :integer
    end
  end
end
