defmodule WizHome.Assistant.Capture.Sink do
  @moduledoc """
  Buffers 16 kHz mono s16le PCM after a wake-word hit and detects end-of-utterance
  by silence, mirroring an adaptive-recording approach: keep listening until the
  peak amplitude stays under threshold for `silence_duration_ms` after speech
  has started, or `max_duration_ms` is hit as a safety cap.

  Sends the controller exactly one message:
    * `{:utterance_captured, pcm_binary, reason}` when speech was heard
    * `{:utterance_timeout, reason}` when nothing crossed the speech threshold
  """

  use Membrane.Sink

  alias Membrane.RawAudio

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}

  def_options controller: [
                spec: pid(),
                description: "PID that receives the utterance result"
              ],
              silence_peak_threshold: [
                spec: non_neg_integer(),
                default: 500,
                description: "s16 peak amplitude below which a chunk counts as silence"
              ],
              silence_duration_ms: [
                spec: pos_integer(),
                default: 1_200,
                description: "Trailing silence (after speech started) that ends capture"
              ],
              max_duration_ms: [
                spec: pos_integer(),
                default: 15_000,
                description: "Hard cap on capture length regardless of silence"
              ],
              min_speech_ms: [
                spec: pos_integer(),
                default: 300,
                description: "Minimum audio above threshold before silence can end capture"
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = opts) do
    {[],
     %{
       controller: opts.controller,
       silence_peak_threshold: opts.silence_peak_threshold,
       silence_duration_ms: opts.silence_duration_ms * 1.0,
       max_duration_ms: opts.max_duration_ms * 1.0,
       min_speech_ms: opts.min_speech_ms * 1.0,
       chunks: [],
       captured_ms: 0.0,
       silence_ms: 0.0,
       speech_started?: false,
       done?: false
     }}
  end

  @impl true
  def handle_stream_format(:input, _fmt, _ctx, state), do: {[], state}

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{done?: true} = state), do: {[], state}

  def handle_buffer(:input, buffer, _ctx, state) do
    payload = buffer.payload
    # s16le mono @ 16kHz: 2 bytes/sample, 16000 samples/sec.
    duration_ms = byte_size(payload) / 2 / 16_000 * 1000
    peak = s16le_peak(payload)

    state = %{state | chunks: [payload | state.chunks], captured_ms: state.captured_ms + duration_ms}

    state =
      if peak >= state.silence_peak_threshold do
        %{state | silence_ms: 0.0, speech_started?: true}
      else
        %{state | silence_ms: state.silence_ms + duration_ms}
      end

    cond do
      state.speech_started? and state.silence_ms >= state.silence_duration_ms and
          state.captured_ms >= state.min_speech_ms ->
        finish(state, :silence)

      state.captured_ms >= state.max_duration_ms ->
        finish(state, :max_duration)

      true ->
        {[], state}
    end
  end

  defp finish(state, reason) do
    audio = state.chunks |> Enum.reverse() |> IO.iodata_to_binary()

    if state.speech_started? do
      send(state.controller, {:utterance_captured, audio, reason})
    else
      send(state.controller, {:utterance_timeout, reason})
    end

    {[], %{state | done?: true}}
  end

  defp s16le_peak(bin) do
    Enum.reduce(for(<<s::little-signed-16 <- bin>>, do: abs(s)), 0, &max/2)
  end
end
