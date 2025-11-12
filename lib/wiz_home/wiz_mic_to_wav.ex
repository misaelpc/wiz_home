defmodule WizHome.MicToWav do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    device_id = Keyword.get(opts, :device_id, :default)
    output_file = Keyword.get(opts, :output_file, "capture.wav")
    channels = Keyword.get(opts, :channels)
    sample_rate = Keyword.get(opts, :sample_rate)

    # Construir el struct condicionalmente para permitir valores por defecto del dispositivo
    source_opts =
      [
        device_id: device_id,
        sample_format: :s16le
      ]
      |> then(fn opts_list ->
        if channels, do: Keyword.put(opts_list, :channels, channels), else: opts_list
      end)
      |> then(fn opts_list ->
        if sample_rate, do: Keyword.put(opts_list, :sample_rate, sample_rate), else: opts_list
      end)

    spec =
      child(:mic, struct(Membrane.PortAudio.Source, source_opts))
      |> child(:wav_serializer, Membrane.WAV.Serializer)
      |> child(:sink, %Membrane.File.Sink{location: output_file})

    {[spec: spec], %{}}
  end
end
