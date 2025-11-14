defmodule TimeOS.EventReceiver do
  @moduledoc """
  Receives and persists events, then notifies evaluator.
  """

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:new_event, event}, state) do
    Logger.info("Received event: type=#{event.type}, id=#{event.id}")
    GenServer.cast(TimeOS.Evaluator, {:new_event, event})
    {:noreply, state}
  end

  def receive_event(event) do
    GenServer.cast(__MODULE__, {:new_event, event})
  end
end
