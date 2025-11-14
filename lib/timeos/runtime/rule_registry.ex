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
      rule_index: %{},
      when_clauses: %{}
    }, {:continue, :load_rules}}
  end

  @impl true
  def handle_continue(:load_rules, state) do
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
  def handle_call({:get_rule_by_id, rule_id}, _from, state) do
    rule = Enum.find(state.rules, &(&1.id == rule_id))
    {:reply, rule, state}
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
  def handle_call({:add_rule, rule_data, when_clause}, _from, state) do
    changeset = TimeRule.changeset(%TimeRule{}, rule_data)

    case Repo.insert(changeset) do
      {:ok, rule} ->
        when_clauses = if when_clause != nil do
          Map.put(state.when_clauses, rule.id, when_clause)
        else
          state.when_clauses
        end

        new_state = %{state |
          rules: [rule | state.rules],
          when_clauses: when_clauses
        }
        Logger.info("Added rule: #{rule.name}")
        {:reply, {:ok, rule}, new_state}

      {:error, reason} ->
        Logger.error("Failed to add rule: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_rule, rule_data}, _from, state) do
    handle_call({:add_rule, rule_data, nil}, nil, state)
  end

  @impl true
  def handle_call({:get_when_clause, rule_id}, _from, state) do
    when_clause = Map.get(state.when_clauses, rule_id)
    {:reply, when_clause, state}
  end

  @impl true
  def handle_call({:reload_rules}, _from, state) do
    rules = Repo.all(from tr in TimeRule, where: tr.enabled == true)
    new_state = %{state | rules: rules}
    Logger.info("Reloaded #{length(rules)} rules from DB")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_rule, rule_id, updates}, _from, state) do
    case Repo.get(TimeRule, rule_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      rule ->
        changeset = TimeRule.changeset(rule, updates)

        case Repo.update(changeset) do
          {:ok, updated_rule} ->
            new_rules = Enum.map(state.rules, fn r ->
              if r.id == rule_id, do: updated_rule, else: r
            end)
            new_state = %{state | rules: new_rules}
            Logger.info("Updated rule: #{updated_rule.name}")
            {:reply, {:ok, updated_rule}, new_state}

          {:error, reason} ->
            Logger.error("Failed to update rule: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:delete_rule, rule_id}, _from, state) do
    case Repo.get(TimeRule, rule_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      rule ->
        case Repo.delete(rule) do
          {:ok, _} ->
            new_rules = Enum.reject(state.rules, &(&1.id == rule_id))
            new_when_clauses = Map.delete(state.when_clauses, rule_id)
            new_state = %{state |
              rules: new_rules,
              when_clauses: new_when_clauses
            }
            Logger.info("Deleted rule: #{rule.name}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to delete rule: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  def get_rules do
    GenServer.call(__MODULE__, {:get_rules})
  end

  def get_rule_by_id(rule_id) do
    GenServer.call(__MODULE__, {:get_rule_by_id, rule_id})
  end

  def get_performers do
    GenServer.call(__MODULE__, {:get_performers})
  end

  def add_rule(rule_data, when_clause \\ nil) do
    GenServer.call(__MODULE__, {:add_rule, rule_data, when_clause})
  end

  def register_performer(mod) do
    GenServer.call(__MODULE__, {:register_performer, mod})
  end

  def get_when_clause(rule_id) do
    GenServer.call(__MODULE__, {:get_when_clause, rule_id})
  end

  def reload_rules do
    GenServer.call(__MODULE__, {:reload_rules})
  end

  def update_rule(rule_id, updates) do
    GenServer.call(__MODULE__, {:update_rule, rule_id, updates})
  end

  def delete_rule(rule_id) do
    GenServer.call(__MODULE__, {:delete_rule, rule_id})
  end
end
