defmodule WizHome.Assistant.WakeWord.Sink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.RawAudio

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}

  def_options controller: [
                spec: pid(),
                description: "PID that receives {:wake_word_scores, scores} messages"
              ],
              detector: [
                spec: struct(),
                description: "%WizHome.Assistant.WakeWord.Detector{}"
              ],
              threshold: [
                spec: float(),
                default: 0.35,
                description: "Score threshold for logging hits"
              ],
              debug: [
                spec: boolean(),
                default: false
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = opts) do
    {[],
     %{
       controller: opts.controller,
       detector: opts.detector,
       threshold: opts.threshold * 1.0,
       debug?: opts.debug
     }}
  end

  @impl true
  def handle_stream_format(:input, _fmt, _ctx, state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {:ok, detector, scores} =
      WizHome.Assistant.WakeWord.Detector.feed(state.detector, buffer.payload)

    state = %{state | detector: detector}

    if scores != %{} do
      send(state.controller, {:wake_word_scores, scores})

      if state.debug? do
        pk = s16le_peak(buffer.payload)
        Membrane.Logger.info("[wake_word] peak=#{pk} scores=#{inspect(scores)}")
      end

      {name, v} = Enum.max_by(scores, fn {_k, val} -> val end, fn -> {nil, 0.0} end)

      if is_binary(name) and v >= state.threshold do
        Membrane.Logger.info("[wake_word] HIT #{name} score=#{Float.round(v, 4)}")
      end
    end

    {[], state}
  end

  defp s16le_peak(bin) do
    Enum.reduce(for(<<s::little-signed-16 <- bin>>, do: abs(s)), 0, &max/2)
  end
end
