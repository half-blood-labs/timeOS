defmodule TimeOS.Schema.ScheduledJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "scheduled_jobs" do
    field :rule_id, :binary_id
    field :event_id, :binary_id
    field :perform_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :status, Ecto.Enum, values: [:pending, :running, :success, :failed, :dead], default: :pending
    field :args, :map
    field :last_error, :string
    field :idempotency_key, :string
    timestamps()
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:rule_id, :event_id, :perform_at, :attempt_count, :max_attempts, :status, :args, :last_error, :idempotency_key])
    |> validate_required([:rule_id, :perform_at])
    |> unique_constraint(:idempotency_key, name: :scheduled_jobs_idempotency_key_unique)
  end

  def mark_running(job) do
    change(job, status: :running, attempt_count: job.attempt_count + 1)
  end

  def mark_success(job) do
    change(job, status: :success, last_error: nil)
  end

  def mark_failed(job, reason) do
    change(job, status: :failed, last_error: reason)
  end

  def mark_dead(job, reason) do
    change(job, status: :dead, last_error: reason)
  end
end
