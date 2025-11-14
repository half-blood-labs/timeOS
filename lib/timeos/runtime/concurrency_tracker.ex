defmodule TimeOS.ConcurrencyTracker do
  @moduledoc """
  Tracks concurrent job executions per rule to enforce concurrency limits.
  """

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    {:ok, %{counts: %{}}}
  end

  @doc """
  Check if a rule can execute another job (under concurrency limit).
  Returns {:ok, :allowed} if under limit, {:error, :limit_exceeded} otherwise.
  """
  def check_limit(rule_id, limit) when is_binary(rule_id) do
    GenServer.call(__MODULE__, {:check_limit, rule_id, limit})
  end

  @doc """
  Increment the count of running jobs for a rule.
  Returns {:ok, count} with new count.
  """
  def increment(rule_id) when is_binary(rule_id) do
    GenServer.call(__MODULE__, {:increment, rule_id})
  end

  @doc """
  Decrement the count of running jobs for a rule.
  """
  def decrement(rule_id) when is_binary(rule_id) do
    GenServer.cast(__MODULE__, {:decrement, rule_id})
  end

  @doc """
  Get the current count of running jobs for a rule.
  """
  def get_count(rule_id) when is_binary(rule_id) do
    GenServer.call(__MODULE__, {:get_count, rule_id})
  end

  @impl true
  def handle_call({:check_limit, _rule_id, limit}, _from, state)
      when is_nil(limit) or limit <= 0 do
    # No limit set, always allow
    {:reply, {:ok, :allowed}, state}
  end

  @impl true
  def handle_call({:check_limit, rule_id, limit}, _from, state) do
    current_count = Map.get(state.counts, rule_id, 0)

    if current_count < limit do
      {:reply, {:ok, :allowed}, state}
    else
      {:reply, {:error, :limit_exceeded}, state}
    end
  end

  @impl true
  def handle_call({:increment, rule_id}, _from, state) do
    current_count = Map.get(state.counts, rule_id, 0)
    new_count = current_count + 1
    new_state = %{state | counts: Map.put(state.counts, rule_id, new_count)}
    {:reply, {:ok, new_count}, new_state}
  end

  @impl true
  def handle_call({:get_count, rule_id}, _from, state) do
    count = Map.get(state.counts, rule_id, 0)
    {:reply, count, state}
  end

  @impl true
  def handle_cast({:decrement, rule_id}, state) do
    current_count = Map.get(state.counts, rule_id, 0)
    new_count = max(0, current_count - 1)

    new_state =
      if new_count == 0 do
        %{state | counts: Map.delete(state.counts, rule_id)}
      else
        %{state | counts: Map.put(state.counts, rule_id, new_count)}
      end

    {:noreply, new_state}
  end
end
