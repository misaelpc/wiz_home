defmodule WizHome.Assistant.Conversation.Orchestrator do
  @moduledoc """
  Drives the listen → capture → transcribe loop.

  Owns the wake-word detector (loaded once, reused across restarts) and
  toggles between `WakeWord.Pipeline` and `Capture.Pipeline` so only one of
  them holds the microphone at a time:

      idle → wake pipeline running (listening)
           → wake word hit → capture pipeline running (recording command)
           → silence/timeout → whisper.cpp transcription → back to listening
  """

  use GenServer

  require Logger

  alias WizHome.Assistant.Audio.Wav
  alias WizHome.Assistant.Brain.Actions
  alias WizHome.Assistant.Brain.Ollama, as: Brain
  alias WizHome.Assistant.Capture
  alias WizHome.Assistant.Speech.Whisper
  alias WizHome.Assistant.WakeWord

  @pipeline_stop_settle_ms 200
  @status_topic "assistant:status"

  def status_topic, do: @status_topic

  def current_status do
    GenServer.call(__MODULE__, :current_status)
  catch
    :exit, _ -> :idle
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :start_wake_pipeline)
    {:ok, %{mode: :starting, pipeline: nil, ref: nil, detector: nil, status: :idle}}
  end

  @impl true
  def handle_call(:current_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:start_wake_pipeline, state) do
    case Process.whereis(WakeWord.Listener) do
      nil ->
        Process.send_after(self(), :start_wake_pipeline, 500)
        {:noreply, state}

      listener ->
        start_wake_pipeline(listener, state)
    end
  end

  def handle_info({:wake_word_hit, name, score}, %{mode: :listening} = state) do
    Logger.info(
      "[Orchestrator] Wake word '#{name}' (#{Float.round(score, 3)}) -> capturing command"
    )

    stop_pipeline(state.pipeline, state.ref)

    case Membrane.Pipeline.start_link(Capture.Pipeline, controller: self()) do
      {:ok, _sup, pipeline} ->
        ref = Process.monitor(pipeline)
        state = broadcast_status(state, :capturing)
        {:noreply, %{state | mode: :capturing, pipeline: pipeline, ref: ref}}

      {:error, reason} ->
        Logger.warning("[Orchestrator] Capture pipeline start failed: #{inspect(reason)}")
        send(self(), :start_wake_pipeline)
        {:noreply, %{state | mode: :idle, pipeline: nil, ref: nil}}
    end
  end

  def handle_info({:wake_word_hit, _name, _score}, state), do: {:noreply, state}

  def handle_info({:utterance_captured, pcm, reason}, %{mode: :capturing} = state) do
    Logger.info(
      "[Orchestrator] Utterance captured (#{byte_size(pcm)} bytes, ended: #{reason}), transcribing..."
    )

    stop_pipeline(state.pipeline, state.ref)
    state = broadcast_status(state, :transcribing)
    transcribe_and_restart(pcm)
    {:noreply, %{state | mode: :idle, pipeline: nil, ref: nil}}
  end

  def handle_info({:utterance_timeout, _reason}, %{mode: :capturing} = state) do
    Logger.info("[Orchestrator] No speech detected, back to listening")
    stop_pipeline(state.pipeline, state.ref)
    send(self(), :start_wake_pipeline)
    {:noreply, %{state | mode: :idle, pipeline: nil, ref: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref} = state) do
    if reason != :normal do
      Logger.warning("[Orchestrator] Pipeline crashed: #{inspect(reason)}, restarting listening")
    end

    send(self(), :start_wake_pipeline)
    {:noreply, %{state | mode: :idle, pipeline: nil, ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp start_wake_pipeline(listener, state) do
    with {:ok, detector} <- get_or_load_detector(state),
         {:ok, _sup, pipeline} <-
           Membrane.Pipeline.start_link(WakeWord.Pipeline, controller: listener, detector: detector) do
      ref = Process.monitor(pipeline)
      Logger.info("[Orchestrator] Listening for wake word")
      state = broadcast_status(state, :listening)
      {:noreply, %{state | mode: :listening, pipeline: pipeline, ref: ref, detector: detector}}
    else
      {:error, reason} ->
        Logger.warning("[Orchestrator] Wake pipeline start failed: #{inspect(reason)}")
        Process.send_after(self(), :start_wake_pipeline, 5_000)
        {:noreply, %{state | mode: :idle, pipeline: nil, ref: nil}}
    end
  end

  defp get_or_load_detector(%{detector: nil}), do: WakeWord.Detector.load()
  defp get_or_load_detector(%{detector: %WakeWord.Detector{} = detector}), do: {:ok, detector}

  defp transcribe_and_restart(pcm) do
    wav_path = Path.join(System.tmp_dir!(), "beemo_utterance_#{System.unique_integer([:positive])}.wav")
    Wav.write!(wav_path, pcm)

    case Whisper.transcribe(wav_path) do
      {:ok, ""} -> Logger.info("[Orchestrator] Heard nothing.")
      {:ok, text} -> respond_to(text)
      {:error, reason} -> Logger.warning("[Orchestrator] Transcription failed: #{inspect(reason)}")
    end

    File.rm(wav_path)
    send(self(), :start_wake_pipeline)
  end

  defp respond_to(text) do
    Logger.info("[Orchestrator] Heard: #{inspect(text)}")

    case Brain.ask(text) do
      {:ok, reply} -> Logger.info("[Orchestrator] Bot: #{Actions.resolve(reply)}")
      {:error, reason} -> Logger.warning("[Orchestrator] Ollama request failed: #{inspect(reason)}")
    end
  end

  defp broadcast_status(state, status) do
    Phoenix.PubSub.broadcast(WizHome.PubSub, @status_topic, {:assistant_status, status})
    %{state | status: status}
  end

  defp stop_pipeline(nil, _ref), do: :ok

  defp stop_pipeline(pipeline, ref) do
    if ref, do: Process.demonitor(ref, [:flush])
    Membrane.Pipeline.terminate(pipeline, timeout: 5_000, force?: true)
    # PortAudio needs a beat to release the device before the next pipeline opens it.
    Process.sleep(@pipeline_stop_settle_ms)
  end
end
