defmodule TimeOS.TimezoneUtils do
  @moduledoc """
  Timezone utilities for scheduling.
  """

  def to_timezone(datetime, nil), do: {:ok, datetime}

  def to_timezone(datetime, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, dt} -> {:ok, dt}
      error -> error
    end
  end

  def to_timezone(datetime, _), do: {:ok, datetime}

  def to_utc(datetime) do
    case DateTime.shift_zone(datetime, "Etc/UTC") do
      {:ok, dt} -> {:ok, dt}
      error -> error
    end
  end

  def now_in_timezone(timezone) do
    DateTime.utc_now()
    |> to_timezone(timezone)
    |> elem(1)
  end
end
