defmodule TimeOS.Schema.TimeRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "time_rules" do
    field :name, :string
    field :compiled, :map
    field :module, :string
    field :enabled, :boolean, default: true
    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :compiled, :module, :enabled])
    |> validate_required([:name, :compiled])
    |> unique_constraint(:name)
  end
end
