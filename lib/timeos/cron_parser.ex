defmodule TimeOS.CronParser do
  @moduledoc """
  Simple cron expression parser for scheduling.
  Supports: minute hour day_of_month month day_of_week
  """

  def parse(cron_expr) when is_binary(cron_expr) do
    parts = String.split(cron_expr, " ")

    case length(parts) do
      5 ->
        [minute, hour, day_of_month, month, day_of_week] = parts

        {:ok,
         %{
           minute: parse_field(minute, 0..59),
           hour: parse_field(hour, 0..23),
           day_of_month: parse_field(day_of_month, 1..31),
           month: parse_field(month, 1..12),
           day_of_week: parse_field(day_of_week, 0..6)
         }}

      _ ->
        {:error, :invalid_format}
    end
  end

  def parse(_), do: {:error, :invalid_format}

  def next_execution_time(cron_expr, from_time \\ DateTime.utc_now()) do
    case parse(cron_expr) do
      {:ok, schedule} ->
        calculate_next(schedule, from_time)

      error ->
        error
    end
  end

  defp parse_field("*", _range), do: :all

  defp parse_field(field, range) when is_binary(field) do
    case Integer.parse(field) do
      {num, ""} ->
        if num in range, do: {:value, num}, else: {:error, :out_of_range}

      _ ->
        {:error, :invalid}
    end
  end

  defp calculate_next(schedule, from_time) do
    current = from_time
    year = current.year
    month = current.month
    day = current.day
    hour = current.hour
    minute = current.minute

    candidate = %DateTime{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: 0,
      microsecond: {0, 6},
      std_offset: 0,
      utc_offset: 0,
      zone_abbr: "UTC",
      time_zone: "Etc/UTC"
    }

    find_next_valid(schedule, candidate, 0)
  end

  defp find_next_valid(_schedule, _candidate, attempts) when attempts > 365 * 24 * 60 do
    {:error, :no_valid_time_found}
  end

  defp find_next_valid(schedule, candidate, attempts) do
    if matches?(schedule, candidate) do
      if DateTime.compare(candidate, DateTime.utc_now()) == :gt do
        {:ok, candidate}
      else
        next = DateTime.add(candidate, 60, :second)
        find_next_valid(schedule, next, attempts + 1)
      end
    else
      next = DateTime.add(candidate, 60, :second)
      find_next_valid(schedule, next, attempts + 1)
    end
  end

  defp matches?(schedule, datetime) do
    matches_field?(schedule.minute, datetime.minute) and
      matches_field?(schedule.hour, datetime.hour) and
      matches_field?(schedule.day_of_month, datetime.day) and
      matches_field?(schedule.month, datetime.month) and
      matches_field?(schedule.day_of_week, day_of_week(datetime))
  end

  defp matches_field?(:all, _), do: true
  defp matches_field?({:value, val}, actual), do: val == actual
  defp matches_field?(_, _), do: false

  defp day_of_week(datetime) do
    :calendar.day_of_the_week(datetime.year, datetime.month, datetime.day) - 1
  end
end
