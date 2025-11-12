defmodule WizHome.Voice.VoicePipeline do
  @moduledoc """
  Pipeline de Membrane para captura y procesamiento de audio en tiempo real.

  Flujo: PortAudio.Source → AudioChunkFilter → (opcional: WAV Serializer para debug)
  """

  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    device_id = Keyword.get(opts, :device_id, :default)
    controller_pid = Keyword.get(opts, :controller_pid)
    channels = Keyword.get(opts, :channels)
    sample_rate = Keyword.get(opts, :sample_rate)
    chunk_duration_ms = Keyword.get(opts, :chunk_duration_ms, 3000)
    debug_output = Keyword.get(opts, :debug_output)

    if is_nil(controller_pid) do
      raise ArgumentError, "controller_pid es requerido"
    end

    # Construir opciones del source
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

    # Construir el pipeline
    # El filter procesa los chunks y los envía al controller
    # También reenvía al output para mantener el stream (aunque no esté conectado)
    spec =
      child(:mic, struct(Membrane.PortAudio.Source, source_opts))
      |> child(:chunk_filter, %WizHome.Voice.AudioChunkFilter{
        controller_pid: controller_pid,
        chunk_duration_ms: chunk_duration_ms
      })

    # Opcional: agregar serializer WAV para debug
    # Si no hay debug, usar Fake.Sink para descartar los datos del output
    spec =
      if debug_output do
        spec
        |> child(:wav_serializer, Membrane.WAV.Serializer)
        |> child(:sink, %Membrane.File.Sink{location: debug_output})
      else
        # Conectar a Fake.Sink para descartar los datos (el filter ya procesó los chunks)
        spec
        |> child(:fake_sink, Membrane.Fake.Sink)
      end

    {[spec: spec], %{}}
  end
end
