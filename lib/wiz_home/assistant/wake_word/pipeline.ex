defmodule WizHome.Assistant.WakeWord.Pipeline do
  @moduledoc """
  Membrane pipeline: PortAudio mic → FFmpeg resample (16 kHz mono s16le) → WakeWord Sink.
  """

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @s16_16k %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}
  @max_timer :ww_max
  @default_mic_toilet 50_000
  @default_post_toilet 32_000

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    controller = Keyword.fetch!(opts, :controller)
    max_seconds = Keyword.get(opts, :max_seconds, 0)
    threshold = Keyword.get(opts, :threshold, 0.35) * 1.0
    debug? = Keyword.get(opts, :debug, false)

    detector =
      case Keyword.fetch(opts, :detector) do
        {:ok, %WizHome.Assistant.WakeWord.Detector{} = d} ->
          d

        _ ->
          case WizHome.Assistant.WakeWord.Detector.load(Keyword.get(opts, :detector_opts, [])) do
            {:ok, d} -> d
            {:error, e} -> raise ArgumentError, "Detector load failed: #{inspect(e)}"
          end
      end

    device_id =
      Keyword.get(opts, :device_id) ||
        Application.get_env(:wiz_home, :portaudio_input_device_id, :default)

    spec =
      child(:mic_source, %Membrane.PortAudio.Source{
        device_id: device_id,
        sample_format: :s16le,
        channels: Keyword.get(opts, :channels, 2),
        sample_rate: Keyword.get(opts, :sample_rate, 44_100),
        latency: :low
      })
      |> via_in(:input, toilet_capacity: @default_mic_toilet)
      |> child(:resample, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: @s16_16k
      })
      |> via_in(:input, toilet_capacity: @default_post_toilet)
      |> child(:ww_sink, %WizHome.Assistant.WakeWord.Sink{
        controller: controller,
        detector: detector,
        threshold: threshold,
        debug: debug?
      })

    actions = [spec: spec]

    actions =
      if max_seconds > 0 do
        actions ++ [start_timer: {@max_timer, Membrane.Time.seconds(max_seconds)}]
      else
        actions
      end

    {actions, %{controller: controller}}
  end

  @impl true
  def handle_tick(@max_timer, _ctx, st) do
    send(st.controller, {:wake_word_timeout})
    {[stop_timer: @max_timer, terminate: :normal], st}
  end
end
