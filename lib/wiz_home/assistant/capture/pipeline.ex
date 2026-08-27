defmodule WizHome.Assistant.Capture.Pipeline do
  @moduledoc """
  Membrane pipeline: PortAudio mic → FFmpeg resample (16 kHz mono s16le) → Capture.Sink.

  Same mic → resample shape as `WizHome.Assistant.WakeWord.Pipeline`, started instead
  of it once a wake word fires, so only one pipeline holds the audio device at a time.
  """

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @s16_16k %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    controller = Keyword.fetch!(opts, :controller)

    device_id =
      Keyword.get(opts, :device_id) ||
        Application.get_env(:wiz_home, :portaudio_input_device_id, :default)

    sink_opts = [
      controller: controller,
      silence_peak_threshold:
        Keyword.get(
          opts,
          :silence_peak_threshold,
          Application.get_env(:wiz_home, :capture_silence_peak_threshold, 500)
        ),
      silence_duration_ms:
        Keyword.get(
          opts,
          :silence_duration_ms,
          Application.get_env(:wiz_home, :capture_silence_duration_ms, 1_200)
        ),
      max_duration_ms:
        Keyword.get(
          opts,
          :max_duration_ms,
          Application.get_env(:wiz_home, :capture_max_duration_ms, 15_000)
        )
    ]

    spec =
      child(:mic_source, %Membrane.PortAudio.Source{
        device_id: device_id,
        sample_format: :s16le,
        channels: Keyword.get(opts, :channels, 2),
        sample_rate: Keyword.get(opts, :sample_rate, 44_100),
        latency: :low
      })
      |> via_in(:input, toilet_capacity: 50_000)
      |> child(:resample, %Membrane.FFmpeg.SWResample.Converter{output_stream_format: @s16_16k})
      |> via_in(:input, toilet_capacity: 32_000)
      |> child(:capture_sink, struct(WizHome.Assistant.Capture.Sink, sink_opts))

    {[spec: spec], %{controller: controller}}
  end
end
