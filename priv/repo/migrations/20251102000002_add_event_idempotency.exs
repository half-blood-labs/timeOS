defmodule TimeOS.Repo.Migrations.AddEventIdempotency do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :idempotency_key, :string
    end

    create unique_index(:events, [:idempotency_key], name: :events_idempotency_key_unique)
  end
end
