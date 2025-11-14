defmodule TimeOS.Schema.TimeRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "time_rules" do
    field(:name, :string)
    field(:compiled, :map)
    field(:module, :string)
    field(:enabled, :boolean, default: true)
    field(:cron_expression, :string)
    field(:priority, :integer, default: 0)
    field(:rate_limit_per_minute, :integer)
    field(:timezone, :string)
    field(:concurrency_limit, :integer)
    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :name,
      :compiled,
      :module,
      :enabled,
      :cron_expression,
      :priority,
      :rate_limit_per_minute,
      :timezone,
      :concurrency_limit
    ])
    |> validate_required([:name, :compiled])
    |> unique_constraint(:name)
  end
end
