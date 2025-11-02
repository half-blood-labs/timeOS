defmodule DSLTest do
  use ExUnit.Case

  describe "time helper macros" do
    test "days/1 calculates milliseconds correctly" do
      import TimeOS.DSL.RuleSet
      d = days(1)
      assert d == 1 * 24 * 3600 * 1000
    end

    test "hours/1 calculates milliseconds correctly" do
      import TimeOS.DSL.RuleSet
      h = hours(2)
      assert h == 2 * 3600 * 1000
    end

    test "minutes/1 calculates milliseconds correctly" do
      import TimeOS.DSL.RuleSet
      m = minutes(30)
      assert m == 30 * 60 * 1000
    end

    test "seconds/1 calculates milliseconds correctly" do
      import TimeOS.DSL.RuleSet
      s = seconds(60)
      assert s == 60 * 1000
    end
  end
end
