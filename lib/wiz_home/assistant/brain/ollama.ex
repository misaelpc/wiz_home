defmodule WizHome.Assistant.Brain.Ollama do
  @moduledoc """
  Chat client for the local Ollama server.

  Tool calls are not requested via Ollama's native `tools` API — small models
  like gemma3:1b don't reliably support it. Instead the system prompt asks
  the model to reply with a JSON `{"action": ...}` blob for recognized
  actions and plain conversational text otherwise, same approach be-more-agent
  uses in `agent.py`.
  """

  # Asking a 1B model to sometimes emit JSON and sometimes prose is unreliable —
  # it pattern-matches every reply to JSON regardless of intent, even greetings.
  # Forcing ONE consistent JSON shape for every reply (via Ollama's schema-
  # constrained `format`) and giving "chat" its own action is far more reliable
  # than a bare "reply with text otherwise" instruction.
  @system_prompt """
  You are a helpful voice assistant running on a Raspberry Pi.
  Style: short, friendly sentences, spoken out loud.
  Always respond with the required JSON shape.

  - If the user asks for the current time, set "action" to "get_time".
  - If the user asks to turn the lights on, set "action" to "turn_on_lights".
  - If the user asks to turn the lights off, set "action" to "turn_off_lights".
  - For anything else — including requests you cannot actually do — set "action"
    to "chat" and put your short spoken reply in "text". Never use "get_time" or
    the light actions unless the user is specifically asking for that.

  ### EXAMPLES ###

  User: What time is it?
  You: {"action": "get_time"}

  User: Turn on the lights.
  You: {"action": "turn_on_lights"}

  User: Can you kill the lights?
  You: {"action": "turn_off_lights"}

  User: Hello!
  You: {"action": "chat", "text": "Hi there! How can I help?"}

  User: Tell me a fun fact about bees.
  You: {"action": "chat", "text": "Bees can recognize human faces!"}

  ### END EXAMPLES ###
  """

  @response_schema %{
    "type" => "object",
    "properties" => %{
      "action" => %{
        "type" => "string",
        "enum" => ["get_time", "turn_on_lights", "turn_off_lights", "chat"]
      },
      "text" => %{"type" => "string"}
    },
    "required" => ["action"]
  }

  # Keep the small model on-rails: low temperature curbs rambling, repeat_penalty
  # discourages the token-repetition loops small models fall into (observed on
  # "tell me a joke" — it looped on an emoji until num_predict cut it off mid-JSON),
  # and num_predict caps how long a runaway generation can go before that happens.
  @generation_options %{"temperature" => 0.3, "repeat_penalty" => 1.3, "num_predict" => 120}

  @doc "Sends transcribed text to Ollama and returns the raw assistant reply (JSON text)."
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(text, opts \\ []) when is_binary(text) do
    model = Keyword.get(opts, :model, config(:ollama_model, "gemma3:1b"))
    client = Ollama.init(config(:ollama_base_url, "http://localhost:11434/api"))

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: text}
    ]

    case Ollama.chat(client,
           model: model,
           messages: messages,
           format: @response_schema,
           options: @generation_options,
           stream: false
         ) do
      {:ok, %{"message" => %{"content" => content}}} -> {:ok, String.trim(content)}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp config(key, default), do: Application.get_env(:wiz_home, key, default)
end
