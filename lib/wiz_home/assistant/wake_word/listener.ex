defmodule WizHome.Assistant.WakeWord.Listener do
  @moduledoc """
  Receives raw per-chunk wake word scores, debounces them against a threshold
  and cooldown, and forwards confirmed hits to `WizHome.Assistant.Conversation.Orchestrator`.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    cooldown = Application.get_env(:wiz_home, :wake_word_cooldown_ms, 2_000)
    Logger.info("[WizHome.Assistant] Wake word listener started")
    {:ok, %{last_detection: nil, cooldown_ms: cooldown}}
  end

  @impl true
  def handle_info({:wake_word_scores, scores}, state) do
    threshold = Application.get_env(:wiz_home, :wake_word_threshold, 0.35)
    now = System.monotonic_time(:millisecond)

    {name, score} =
      Enum.max_by(scores, fn {_k, v} -> v end, fn -> {nil, 0.0} end)

    if is_binary(name) and score > 0.01 do
      Logger.debug("[wake_word] #{name}: #{Float.round(score, 4)}")
    end

    # System.monotonic_time/1 is not zero-based (it can start from a large
    # negative offset), so "no detection yet" must be `nil`, not `0` — comparing
    # against `0` made the cooldown check always fail and this branch dead code.
    cooldown_elapsed? =
      case state.last_detection do
        nil -> true
        last -> now - last >= state.cooldown_ms
      end

    state =
      if is_binary(name) and score >= threshold and cooldown_elapsed? do
        Logger.info("🎯 Wake word detected: #{name} (score: #{Float.round(score, 4)})")
        notify_orchestrator(name, score)
        %{state | last_detection: now}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:wake_word_timeout}, state) do
    Logger.info("[WizHome.Assistant] Wake word pipeline timed out")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp notify_orchestrator(name, score) do
    case Process.whereis(WizHome.Assistant.Conversation.Orchestrator) do
      nil -> :ok
      pid -> send(pid, {:wake_word_hit, name, score})
    end
  end
end
