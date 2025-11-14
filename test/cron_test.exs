defmodule CronTest do
  use TimeOS.DataCase

  alias TimeOS.CronParser

  describe "Cron parsing" do
    test "parses valid cron expression" do
      cron_expr = "0 9 * * 1"

      {:ok, schedule} = CronParser.parse(cron_expr)

      assert schedule.minute == {:value, 0}
      assert schedule.hour == {:value, 9}
      assert schedule.day_of_month == :all
      assert schedule.month == :all
      assert schedule.day_of_week == {:value, 1}
    end

    test "parses wildcard cron expression" do
      cron_expr = "* * * * *"

      {:ok, schedule} = CronParser.parse(cron_expr)

      assert schedule.minute == :all
      assert schedule.hour == :all
      assert schedule.day_of_month == :all
      assert schedule.month == :all
      assert schedule.day_of_week == :all
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = CronParser.parse("invalid")
      assert {:error, :invalid_format} = CronParser.parse("0 9 *")
    end

    test "next_execution_time calculates next run time" do
      cron_expr = "0 9 * * 1"
      from_time = ~U[2025-01-15 10:00:00.000000Z]

      {:ok, next_time} = CronParser.next_execution_time(cron_expr, from_time)

      assert next_time.hour == 9
      assert next_time.minute == 0
    end

    test "rule with cron expression is stored" do
      rule = insert(:time_rule, cron_expression: "0 9 * * 1")

      assert rule.cron_expression == "0 9 * * 1"
    end
  end

  describe "DSL cron helpers" do
    test "every_monday generates correct cron expression" do
      defmodule TestRules do
        use TimeOS.DSL.RuleSet

        every_monday do
          perform(:weekly_report)
        end
      end

      rules = TestRules.__timeos_rules__()
      rule = List.first(rules)

      assert rule["type"] == "cron"
      assert rule["cron_expression"] == "0 * * * 1"
    end

    test "every_monday with at option sets time" do
      defmodule TestRulesWithTime do
        use TimeOS.DSL.RuleSet

        every_monday at: "09:00" do
          perform(:send_newsletter)
        end
      end

      rules = TestRulesWithTime.__timeos_rules__()
      rule = List.first(rules)

      assert rule["cron_expression"] == "0 9 * * 1"
    end

    test "every_tuesday generates correct cron" do
      defmodule TestTuesday do
        use TimeOS.DSL.RuleSet

        every_tuesday do
          perform(:task)
        end
      end

      rules = TestTuesday.__timeos_rules__()
      rule = List.first(rules)

      assert rule["cron_expression"] == "0 * * * 2"
    end
  end
end
