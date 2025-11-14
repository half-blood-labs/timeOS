defmodule TimeOS.DSL.RuleSet do
  @moduledoc """
  DSL for declaring temporal rules.

  Usage:
    defmodule MyRules do
      use TimeOS.DSL.RuleSet

      on_event :user_signup, offset: days(2) do
        perform :send_welcome_email
      end

      cron "0 9 * * 1", timezone: "America/New_York" do
        perform :weekly_report
      end

      every_monday at: "09:00", timezone: "UTC" do
        perform :send_newsletter
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

  defmacro cron(cron_expr, opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        unquote(cron_expr),
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_monday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 1",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_tuesday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 2",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_wednesday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 3",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_thursday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 4",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_friday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 5",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_saturday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 6",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro every_sunday(opts \\ [], do: block) do
    quote do
      @timeos_rules {
        :cron,
        "0 * * * 0",
        unquote(opts),
        unquote(Macro.escape(block))
      }
    end
  end

  defmacro perform(action_name, opts \\ []) do
    quote do
      {:perform, unquote(action_name), unquote(opts)}
    end
  end

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

  defmacro __before_compile__(env) do
    rules = Module.get_attribute(env.module, :timeos_rules, [])

    compiled_rules = rules
      |> Enum.reverse()
      |> Enum.map(&compile_rule/1)

    quote do
      def __timeos_rules__ do
        unquote(Macro.escape(compiled_rules))
      end

      def __timeos_when_clauses__ do
        unquote(Macro.escape(extract_when_clauses(rules)))
      end
    end
  end

  defp extract_when_clauses(rules) do
    Enum.map(rules, fn
      {:on_event, _event_type, opts, _block} ->
        Keyword.get(opts, :when, nil)
      _ ->
        nil
    end)
  end

  defp compile_rule({:on_event, event_type, opts, block}) do
    offset_ms = Keyword.get(opts, :offset, 0)
    when_pred = Keyword.get(opts, :when, nil)

    actions = extract_actions(block)
    |> Enum.map(fn {:perform, action, opts} ->
      %{
        "action" => normalize_for_json(action),
        "opts" => normalize_for_json(opts)
      }
    end)

    event_type_str = normalize_event_type_for_json(event_type)

    compiled = %{
      "type" => "on_event",
      "event_type" => event_type_str,
      "offset_ms" => offset_ms,
      "actions" => actions
    }

    if when_pred != nil do
      Map.put(compiled, "when_present", true)
    else
      compiled
    end
  end

  defp compile_rule({:every, interval, opts, block}) do
    actions = extract_actions(block)
    |> Enum.map(fn {:perform, action, opts} ->
      %{
        "action" => normalize_for_json(action),
        "opts" => normalize_for_json(opts)
      }
    end)

    compiled = %{
      "type" => "every",
      "interval_ms" => interval,
      "actions" => actions
    }

    if timezone = Keyword.get(opts, :timezone) do
      Map.put(compiled, "timezone", timezone)
    else
      compiled
    end
  end

  defp compile_rule({:cron, cron_expr, opts, block}) do
    actions = extract_actions(block)
    |> Enum.map(fn {:perform, action, opts} ->
      %{
        "action" => normalize_for_json(action),
        "opts" => normalize_for_json(opts)
      }
    end)

    %{
      "type" => "cron",
      "cron_expression" => normalize_cron_expr(cron_expr, opts),
      "actions" => actions
    }
  end

  defp normalize_cron_expr(cron_expr, opts) when is_binary(cron_expr) do
    if at = Keyword.get(opts, :at) do
      {hour, minute} = parse_time(at)
      parts = String.split(cron_expr, " ")
      [_minute_str, _hour_str | rest] = parts
      "#{minute} #{hour} #{Enum.join(rest, " ")}"
    else
      cron_expr
    end
  end

  defp normalize_cron_expr(cron_expr, _), do: cron_expr

  defp parse_time(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [h, m] ->
        {String.to_integer(h), String.to_integer(m)}
      _ ->
        {0, 0}
    end
  end

  defp normalize_for_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)
  defp normalize_for_json(value) when is_map(value), do: Map.new(value, fn {k, v} -> {normalize_for_json(k), normalize_for_json(v)} end)
  defp normalize_for_json(value), do: value

  defp normalize_event_type_for_json(event_type) when is_atom(event_type), do: Atom.to_string(event_type)
  defp normalize_event_type_for_json(event_type) when is_binary(event_type), do: event_type
  defp normalize_event_type_for_json(_), do: ""

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
