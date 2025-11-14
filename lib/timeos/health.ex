defmodule TimeOS.Health do
  @moduledoc """
  Health check module for system monitoring.
  """

  alias TimeOS.Repo
  import Ecto.Query

  def check do
    %{
      status: overall_status(),
      components: %{
        database: check_database(),
        rule_registry: check_rule_registry(),
        evaluator: check_evaluator(),
        scheduler: check_scheduler(),
        rate_limiter: check_rate_limiter()
      },
      metrics: get_metrics()
    }
  end

  defp overall_status do
    components = [
      check_database(),
      check_rule_registry(),
      check_evaluator(),
      check_scheduler(),
      check_rate_limiter()
    ]

    if Enum.all?(components, &(&1.status == :healthy)) do
      :healthy
    else
      :degraded
    end
  end

  defp check_database do
    try do
      Repo.query!("SELECT 1", [])
      %{status: :healthy, message: "Database connection OK"}
    rescue
      e ->
        %{status: :unhealthy, message: "Database error: #{Exception.message(e)}"}
    end
  end

  defp check_rule_registry do
    case Process.whereis(TimeOS.RuleRegistry) do
      nil ->
        %{status: :unhealthy, message: "RuleRegistry not running"}

      pid when is_pid(pid) ->
        try do
          TimeOS.RuleRegistry.get_rules()
          %{status: :healthy, message: "RuleRegistry OK"}
        catch
          :exit, _ -> %{status: :unhealthy, message: "RuleRegistry not responding"}
        end
    end
  end

  defp check_evaluator do
    case Process.whereis(TimeOS.Evaluator) do
      nil -> %{status: :unhealthy, message: "Evaluator not running"}
      _pid -> %{status: :healthy, message: "Evaluator OK"}
    end
  end

  defp check_scheduler do
    case Process.whereis(TimeOS.Scheduler) do
      nil -> %{status: :unhealthy, message: "Scheduler not running"}
      _pid -> %{status: :healthy, message: "Scheduler OK"}
    end
  end

  defp check_rate_limiter do
    case Process.whereis(TimeOS.RateLimiter) do
      nil -> %{status: :unhealthy, message: "RateLimiter not running"}
      _pid -> %{status: :healthy, message: "RateLimiter OK"}
    end
  end

  defp get_metrics do
    %{
      pending_jobs: count_jobs(:pending),
      running_jobs: count_jobs(:running),
      failed_jobs: count_jobs(:failed),
      dead_letter_jobs: count_dead_letter_jobs(),
      total_rules: count_rules(),
      enabled_rules: count_enabled_rules()
    }
  end

  defp count_jobs(status) do
    from(j in TimeOS.Schema.ScheduledJob, where: j.status == ^status)
    |> Repo.aggregate(:count, :id)
  rescue
    _ -> 0
  end

  defp count_dead_letter_jobs do
    from(j in TimeOS.Schema.ScheduledJob, where: j.dead_letter_queue == true)
    |> Repo.aggregate(:count, :id)
  rescue
    _ -> 0
  end

  defp count_rules do
    from(r in TimeOS.Schema.TimeRule)
    |> Repo.aggregate(:count, :id)
  rescue
    _ -> 0
  end

  defp count_enabled_rules do
    from(r in TimeOS.Schema.TimeRule, where: r.enabled == true)
    |> Repo.aggregate(:count, :id)
  rescue
    _ -> 0
  end
end
