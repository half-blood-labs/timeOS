defmodule RuleManagementTest do
  use TimeOS.DataCase

  describe "Rule management" do
    test "load_rules_from_module loads rules from DSL" do
      defmodule TestRulesModule do
        use TimeOS.DSL.RuleSet

        on_event :user_signup, offset: days(2) do
          perform :send_welcome_email
        end
      end

      results = TimeOS.load_rules_from_module(TestRulesModule)

      assert length(results) == 1
      {:ok, rule} = List.first(results)
      assert rule.name =~ "TestRulesModule"
      assert rule.enabled == true
    end

    test "list_rules returns all rules" do
      rule1 = insert(:time_rule)
      rule2 = insert(:time_rule)

      TimeOS.reload_rules()
      rules = TimeOS.list_rules()

      assert length(rules) >= 2
      assert Enum.any?(rules, &(&1.id == rule1.id))
      assert Enum.any?(rules, &(&1.id == rule2.id))
    end

    test "get_rule returns rule by id" do
      rule = insert(:time_rule)

      TimeOS.reload_rules()
      found = TimeOS.get_rule(rule.id)

      assert found.id == rule.id
      assert found.name == rule.name
    end

    test "enable_rule enables a rule" do
      rule = insert(:time_rule, enabled: false)

      {:ok, updated} = TimeOS.enable_rule(rule.id, true)

      assert updated.enabled == true
    end

    test "enable_rule disables a rule" do
      rule = insert(:time_rule, enabled: true)

      {:ok, updated} = TimeOS.enable_rule(rule.id, false)

      assert updated.enabled == false
    end

    test "update_rule updates rule fields" do
      rule = insert(:time_rule, priority: 0)

      {:ok, updated} = TimeOS.update_rule(rule.id, %{priority: 10})

      assert updated.priority == 10
    end

    test "delete_rule removes rule" do
      rule = insert(:time_rule)

      :ok = TimeOS.delete_rule(rule.id)

      assert Repo.get(TimeOS.Schema.TimeRule, rule.id) == nil
    end

    test "reload_rules reloads from database" do
      _rule1 = insert(:time_rule, enabled: true)
      _rule2 = insert(:time_rule, enabled: false)

      :ok = TimeOS.reload_rules()

      rules = TimeOS.list_rules()
      assert length(rules) >= 1
    end
  end
end
