defmodule TimeOS.RateLimiter do
  @moduledoc """
  Rate limiter for jobs using token bucket algorithm.
  """

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_refill()
    {:ok, %{buckets: %{}}}
  end

  @impl true
  def handle_call({:check_rate_limit, key, limit_per_minute}, _from, state) do
    now = System.system_time(:second)
    bucket = get_or_create_bucket(state.buckets, key, limit_per_minute, now)

    if bucket.tokens > 0 do
      new_bucket = %{bucket | tokens: bucket.tokens - 1, last_refill: now}
      new_state = %{state | buckets: Map.put(state.buckets, key, new_bucket)}
      {:reply, {:ok, :allowed}, new_state}
    else
      wait_seconds = calculate_wait_time(bucket, now)
      {:reply, {:error, :rate_limited, wait_seconds}, state}
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    now = System.system_time(:second)
    new_buckets = refill_all_buckets(state.buckets, now)
    schedule_refill()
    {:noreply, %{state | buckets: new_buckets}}
  end

  def check_rate_limit(key, limit_per_minute) do
    GenServer.call(__MODULE__, {:check_rate_limit, key, limit_per_minute})
  end

  defp get_or_create_bucket(buckets, key, limit_per_minute, now) do
    case Map.get(buckets, key) do
      nil ->
        %{tokens: limit_per_minute, limit: limit_per_minute, last_refill: now}

      bucket ->
        bucket
    end
  end

  defp refill_all_buckets(buckets, now) do
    Enum.reduce(buckets, %{}, fn {key, bucket}, acc ->
      if now - bucket.last_refill >= 60 do
        Map.put(acc, key, %{bucket | tokens: bucket.limit, last_refill: now})
      else
        Map.put(acc, key, bucket)
      end
    end)
  end

  defp calculate_wait_time(bucket, now) do
    elapsed = now - bucket.last_refill

    if elapsed >= 60 do
      0
    else
      60 - elapsed
    end
  end

  defp schedule_refill do
    Process.send_after(self(), :refill_tokens, 60_000)
  end
end
