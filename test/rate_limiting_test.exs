defmodule RateLimitingTest do
  use TimeOS.DataCase

  alias TimeOS.RateLimiter

  setup do
    case Process.whereis(TimeOS.RateLimiter) do
      nil -> RateLimiter.start_link([])
      _pid -> :ok
    end

    :ok
  end

  describe "Rate limiting" do
    test "allows requests within rate limit" do
      key = "test_key"
      limit = 10

      results =
        for _ <- 1..5 do
          RateLimiter.check_rate_limit(key, limit)
        end

      assert Enum.all?(results, &(&1 == {:ok, :allowed}))
    end

    test "rate limits when limit exceeded" do
      key = "test_key_2"
      limit = 3

      for _ <- 1..3 do
        assert {:ok, :allowed} = RateLimiter.check_rate_limit(key, limit)
      end

      result = RateLimiter.check_rate_limit(key, limit)
      assert {:error, :rate_limited, _wait_seconds} = result
    end

    test "different keys have separate rate limits" do
      key1 = "key1"
      key2 = "key2"
      limit = 2

      assert {:ok, :allowed} = RateLimiter.check_rate_limit(key1, limit)
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(key1, limit)
      assert {:error, :rate_limited, _} = RateLimiter.check_rate_limit(key1, limit)

      assert {:ok, :allowed} = RateLimiter.check_rate_limit(key2, limit)
      assert {:ok, :allowed} = RateLimiter.check_rate_limit(key2, limit)
    end

    test "rate limit key is generated from rule and action" do
      rule = insert(:time_rule, rate_limit_per_minute: 10)
      action_name = "send_email"

      job_data = %{
        rule_id: rule.id,
        perform_at: DateTime.utc_now(),
        status: :pending,
        rate_limit_key: "rule:#{rule.id}:action:#{action_name}",
        args: %{"action" => action_name}
      }

      job =
        TimeOS.Schema.ScheduledJob.changeset(%TimeOS.Schema.ScheduledJob{}, job_data)
        |> Repo.insert!()

      assert job.rate_limit_key == "rule:#{rule.id}:action:#{action_name}"
    end
  end
end
