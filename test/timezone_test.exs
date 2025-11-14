defmodule TimezoneTest do
  use TimeOS.DataCase

  alias TimeOS.TimezoneUtils

  describe "Timezone support" do
    test "to_timezone converts datetime to specified timezone" do
      utc_time = ~U[2025-01-15 12:00:00.000000Z]

      {:ok, ny_time} = TimezoneUtils.to_timezone(utc_time, "America/New_York")

      assert ny_time.time_zone == "America/New_York"
    end

    test "to_utc converts datetime back to UTC" do
      utc_time = ~U[2025-01-15 12:00:00.000000Z]

      {:ok, ny_time} = TimezoneUtils.to_timezone(utc_time, "America/New_York")
      {:ok, back_to_utc} = TimezoneUtils.to_utc(ny_time)

      assert back_to_utc.time_zone == "Etc/UTC"
    end

    test "now_in_timezone returns current time in timezone" do
      ny_time = TimezoneUtils.now_in_timezone("America/New_York")

      assert ny_time.time_zone == "America/New_York"
      assert DateTime.utc_now() != nil
    end

    test "job stores timezone" do
      job = insert(:scheduled_job, timezone: "America/New_York")

      assert job.timezone == "America/New_York"
    end

    test "rule stores timezone" do
      rule = insert(:time_rule, timezone: "Europe/London")

      assert rule.timezone == "Europe/London"
    end
  end
end
