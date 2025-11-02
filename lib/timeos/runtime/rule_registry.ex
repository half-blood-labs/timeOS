defmodule TimeOS.RuleRegistry do
  @moduledoc """
  Registry for compiled rules and performer callbacks.
  """

  use GenServer
  require Logger

  alias TimeOS.Schema.TimeRule
  alias TimeOS.Repo
  import Ecto.Query

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{
      rules: [],
      performers: %{},
      rule_index: %{}
    }, {:continue, :load_rules}}
  end

  @impl true
  def handle_continue(:load_rules, state) do
    # Load all enabled rules from DB
    rules = Repo.all(from tr in TimeRule, where: tr.enabled == true)

    new_state = %{state | rules: rules}
    Logger.info("Loaded #{length(rules)} rules from DB")

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_rules}, _from, state) do
    {:reply, state.rules, state}
  end

  @impl true
  def handle_call({:register_performer, mod}, _from, state) do
    performers = Map.put(state.performers, mod, true)
    Logger.info("Registered performer: #{inspect(mod)}")
    {:reply, :ok, %{state | performers: performers}}
  end

  @impl true
  def handle_call({:get_performers}, _from, state) do
    {:reply, state.performers, state}
  end

  @impl true
  def handle_call({:add_rule, rule_data}, _from, state) do
    changeset = TimeRule.changeset(%TimeRule{}, rule_data)

    case Repo.insert(changeset) do
      {:ok, rule} ->
        new_state = %{state | rules: [rule | state.rules]}
        Logger.info("Added rule: #{rule.name}")
        {:reply, {:ok, rule}, new_state}

      {:error, reason} ->
        Logger.error("Failed to add rule: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # Public API helpers
  def get_rules do
    GenServer.call(__MODULE__, {:get_rules})
  end

  def get_performers do
    GenServer.call(__MODULE__, {:get_performers})
  end

  def add_rule(rule_data) do
    GenServer.call(__MODULE__, {:add_rule, rule_data})
  end

  def register_performer(mod) do
    GenServer.call(__MODULE__, {:register_performer, mod})
  end
end
