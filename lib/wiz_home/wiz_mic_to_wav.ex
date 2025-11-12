defmodule WizHome.MicToWav do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    device_id = Keyword.get(opts, :device_id, :default)
    output_file = Keyword.get(opts, :output_file, "capture.wav")

    spec =
      child(:mic, %Membrane.PortAudio.Source{
        device_id: device_id,
        channels: 1,
        sample_rate: 16_000,
        sample_format: :s16le
      })
      |> child(:wav_enc, Membrane.WAV.Encoder)
      |> child(:sink, %Membrane.File.Sink{location: output_file})

    {[spec: spec], %{}}
  end
end
