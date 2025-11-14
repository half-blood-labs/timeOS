defmodule TimeOS.Schema.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "events" do
    field(:type, :string)
    field(:payload, :map)
    field(:occurred_at, :utc_datetime_usec)
    field(:processed, :boolean, default: false)
    field(:idempotency_key, :string)
    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :payload, :occurred_at, :processed, :idempotency_key])
    |> validate_required([:type, :occurred_at])
    |> unique_constraint(:idempotency_key, name: :events_idempotency_key_unique)
  end

  def from_emit(event_type, attrs) do
    type_string = if is_atom(event_type), do: Atom.to_string(event_type), else: event_type

    changeset(%__MODULE__{}, %{
      type: type_string,
      payload: Map.get(attrs, :payload, %{}),
      occurred_at: Map.get(attrs, :occurred_at, DateTime.utc_now()),
      processed: false,
      idempotency_key: Map.get(attrs, :idempotency_key)
    })
  end
end
