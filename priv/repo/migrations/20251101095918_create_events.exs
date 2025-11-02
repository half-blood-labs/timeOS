defmodule TimeOS.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :payload, :jsonb
      add :occurred_at, :utc_datetime_usec, null: false
      add :processed, :boolean, default: false
      timestamps()
    end

    create index(:events, [:type])
    create index(:events, [:occurred_at])
    create index(:events, [:processed])
  end
end
