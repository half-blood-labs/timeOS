defmodule TimeOS.DSL.RuleSet do
  @moduledoc """
  DSL for declaring temporal rules.

  Usage:
    defmodule MyRules do
      use TimeOS.DSL.RuleSet

      on_event :user_signup, offset: days(2) do
        perform :send_welcome_email
      end
    end
  """

  defmacro __using__(_opts) do
    quote do
      import TimeOS.DSL.RuleSet
      Module.register_attribute(__MODULE__, :timeos_rules, accumulate: true)
      @before_compile TimeOS.DSL.RuleSet
    end
  end

  # Trigger: after event + offset
  defmacro on_event(event_type, opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :on_event,
        unquote(event_type),
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  # Trigger: every N intervals
  defmacro every(interval, opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :every,
        unquote(interval),
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  # Action: perform a function
  defmacro perform(action_name, opts \\ []) do
    quote do
      {:perform, unquote(action_name), unquote(opts)}
    end
  end

  # Time helpers
  defmacro days(n) do
    quote do: unquote(n) * 24 * 3600 * 1000
  end

  defmacro hours(n) do
    quote do: unquote(n) * 3600 * 1000
  end

  defmacro minutes(n) do
    quote do: unquote(n) * 60 * 1000
  end

  defmacro seconds(n) do
    quote do: unquote(n) * 1000
  end

  # Compiler hook: runs at compile time
  defmacro __before_compile__(env) do
    rules = Module.get_attribute(env.module, :timeos_rules, [])

    compiled_rules = rules
      |> Enum.reverse()
      |> Enum.map(&compile_rule/1)

    quote do
      def __timeos_rules__ do
        unquote(Macro.escape(compiled_rules))
      end
    end
  end

  # Compile a single rule from DSL to normalized form
  defp compile_rule({:on_event, event_type, opts, block}) do
    offset_ms = Keyword.get(opts, :offset, 0)
    when_pred = Keyword.get(opts, :when, nil)

    actions = extract_actions(block)

    %{
      type: :on_event,
      event_type: event_type,
      offset_ms: offset_ms,
      when: when_pred,
      actions: actions
    }
  end

  defp compile_rule({:every, interval, _opts, block}) do
    actions = extract_actions(block)

    %{
      type: :every,
      interval_ms: interval,
      actions: actions
    }
  end

  # Extract actions from the block
  defp extract_actions({:__block__, _meta, stmts}) do
    Enum.map(stmts, fn
      {:perform, _meta, [action, opts]} when is_list(opts) ->
        {:perform, action, opts}
      {:perform, _meta, [action]} ->
        {:perform, action, []}
    end)
  end

  defp extract_actions(single_stmt) do
    [extract_actions({:__block__, [], [single_stmt]}) |> List.first()]
  end
end
