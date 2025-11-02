defmodule TimeOS.Repo.Migrations.CreateTimeRules do
  use Ecto.Migration

  def change do
    create table(:time_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :compiled, :jsonb, null: false
      add :module, :string
      add :enabled, :boolean, default: true
      timestamps()
    end

    create unique_index(:time_rules, [:name])
  end
end
