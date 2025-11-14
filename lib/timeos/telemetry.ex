defmodule TimeOS.Telemetry do
  @moduledoc """
  Telemetry events for observability.
  """

  def setup do
    :telemetry.attach_many(
      "timeos-handler",
      [
        [:timeos, :event, :emitted],
        [:timeos, :job, :created],
        [:timeos, :job, :started],
        [:timeos, :job, :completed],
        [:timeos, :job, :failed],
        [:timeos, :rule, :matched],
        [:timeos, :rule, :created],
        [:timeos, :rate_limit, :exceeded]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:timeos, :event, :emitted], measurements, metadata, _config) do
    log_metric("event.emitted", measurements, metadata)
  end

  def handle_event([:timeos, :job, :created], measurements, metadata, _config) do
    log_metric("job.created", measurements, metadata)
  end

  def handle_event([:timeos, :job, :started], measurements, metadata, _config) do
    log_metric("job.started", measurements, metadata)
  end

  def handle_event([:timeos, :job, :completed], measurements, metadata, _config) do
    log_metric("job.completed", measurements, metadata)
  end

  def handle_event([:timeos, :job, :failed], measurements, metadata, _config) do
    log_metric("job.failed", measurements, metadata)
  end

  def handle_event([:timeos, :rule, :matched], measurements, metadata, _config) do
    log_metric("rule.matched", measurements, metadata)
  end

  def handle_event([:timeos, :rule, :created], measurements, metadata, _config) do
    log_metric("rule.created", measurements, metadata)
  end

  def handle_event([:timeos, :rate_limit, :exceeded], measurements, metadata, _config) do
    log_metric("rate_limit.exceeded", measurements, metadata)
  end

  defp log_metric(name, measurements, metadata) do
    require Logger

    Logger.debug(
      "Telemetry: #{name} - measurements: #{inspect(measurements)}, metadata: #{inspect(metadata)}"
    )
  end

  def emit_event(category, name, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute([:timeos, category, name], measurements, metadata)
  end
end
