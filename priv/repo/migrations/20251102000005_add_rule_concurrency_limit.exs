defmodule TimeOS.Repo.Migrations.AddRuleConcurrencyLimit do
  use Ecto.Migration

  def change do
    alter table(:time_rules) do
      add :concurrency_limit, :integer
    end
  end
end
