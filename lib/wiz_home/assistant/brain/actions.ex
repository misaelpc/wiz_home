defmodule WizHome.Assistant.Brain.Actions do
  @moduledoc """
  Resolves the JSON `{"action": ...}` replies `Brain.Ollama`'s system prompt
  asks the model for into final, speakable text.
  """

  @doc """
  Turns a raw model reply into the text that should actually be spoken/logged.

  `Brain.Ollama` always requests schema-constrained JSON, so every valid reply
  is `{"action": ...}` — there's no plain-text case to fall back to anymore.
  A reply that fails to parse means the model degenerated (small models can
  fall into token-repetition loops on open-ended prompts like "sing a song"),
  so that gets a friendly fallback too rather than leaking the raw garbage.
  """
  @spec resolve(String.t()) :: String.t()
  def resolve(raw_reply) when is_binary(raw_reply) do
    case extract_json(raw_reply) do
      {:ok, %{"action" => action} = payload} -> run(action, payload)
      _ -> "Sorry, I didn't quite catch that — could you try again?"
    end
  end

  defp run("get_time", _payload) do
    {{_, _, _}, {hour, minute, _}} = :calendar.local_time()
    {period, hour12} = to_12h(hour)
    "The current time is #{pad(hour12)}:#{pad(minute)} #{period}."
  end

  defp run("turn_on_lights", _payload) do
    WizHome.Assistant.Lights.on()
    "Turning the lights on."
  end

  defp run("turn_off_lights", _payload) do
    WizHome.Assistant.Lights.off()
    "Turning the lights off."
  end

  defp run("chat", %{"text" => text}) when is_binary(text) and text != "", do: text
  defp run(_unrecognized, _payload), do: "Sorry, I don't know how to do that yet."

  # Non-greedy: this schema is a flat object, so match the first balanced
  # `{...}` rather than greedily spanning to the last `}` in the whole reply.
  defp extract_json(text) do
    case Regex.run(~r/\{.*?\}/s, text) do
      [json] -> JSON.decode(json)
      nil -> :error
    end
  end

  defp to_12h(0), do: {"AM", 12}
  defp to_12h(hour) when hour < 12, do: {"AM", hour}
  defp to_12h(12), do: {"PM", 12}
  defp to_12h(hour), do: {"PM", hour - 12}

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
