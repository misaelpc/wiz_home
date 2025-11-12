defmodule WizHome.Voice.AudioChunkFilter do
  @moduledoc """
  Filter que acumula buffers de audio y los envía a un GenServer para transcripción.

  Acumula audio en chunks de ~2-3 segundos antes de enviarlos para procesamiento.
  """

  use Membrane.Filter

  alias Membrane.RawAudio

  def_input_pad :input, accepted_format: RawAudio, flow_control: :auto
  def_output_pad :output, accepted_format: RawAudio, flow_control: :auto

  def_options controller_pid: [
                spec: pid(),
                description: "PID del GenServer VoiceController que recibirá los chunks"
              ],
              chunk_duration_ms: [
                spec: pos_integer(),
                default: 3000,
                description: "Duración del chunk en milisegundos antes de enviar"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      controller_pid: opts.controller_pid,
      chunk_duration_ms: opts.chunk_duration_ms,
      accumulated_audio: [],
      accumulated_duration_ms: 0,
      stream_format: nil,
      sample_rate: nil,
      channels: nil
    }

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, %RawAudio{} = stream_format, _ctx, state) do
    # Guardar formato para calcular duración
    new_state = %{
      state
      | stream_format: stream_format,
        sample_rate: stream_format.sample_rate,
        channels: stream_format.channels
    }

    # Reenviar el formato al output
    {[stream_format: {:output, stream_format}], new_state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Calcular duración del buffer en milisegundos
    duration_ms = calculate_buffer_duration(buffer, state)

    # Acumular buffer
    new_accumulated = [buffer | state.accumulated_audio]
    new_duration = state.accumulated_duration_ms + duration_ms

    new_state = %{
      state
      | accumulated_audio: new_accumulated,
        accumulated_duration_ms: new_duration
    }

    # Si alcanzamos la duración objetivo, enviar chunk
    if new_duration >= state.chunk_duration_ms do
      send_chunk(new_state)

      # Reiniciar acumulación
      reset_state = %{
        new_state
        | accumulated_audio: [],
          accumulated_duration_ms: 0
      }

      # Reenviar buffers al output (opcional, para mantener el stream)
      {[buffer: {:output, buffer}], reset_state}
    else
      # Solo reenviar, seguir acumulando
      {[buffer: {:output, buffer}], new_state}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    # Enviar cualquier audio restante antes de terminar
    if length(state.accumulated_audio) > 0 do
      send_chunk(state)
    end

    {[end_of_stream: :output], state}
  end

  # Calcula la duración de un buffer en milisegundos
  defp calculate_buffer_duration(buffer, state) do
    case state.stream_format do
      %RawAudio{sample_rate: sample_rate, channels: channels} when not is_nil(sample_rate) ->
        # Tamaño del buffer en bytes
        buffer_size_bytes = byte_size(buffer.payload)

        # Bytes por muestra (s16le = 2 bytes por muestra)
        bytes_per_sample = 2

        # Número de muestras
        num_samples = div(buffer_size_bytes, bytes_per_sample * channels)

        # Duración en milisegundos
        div(num_samples * 1000, sample_rate)

      _ ->
        # Si no tenemos formato aún, estimar basado en tamaño
        # Asumir 16kHz, mono, s16le como fallback
        buffer_size_bytes = byte_size(buffer.payload)
        estimated_samples = div(buffer_size_bytes, 2)
        div(estimated_samples * 1000, 16_000)
    end
  end

  # Envía un chunk acumulado al VoiceController
  defp send_chunk(state) do
    if length(state.accumulated_audio) > 0 do
      # Revertir la lista para tener los buffers en orden cronológico
      buffers = Enum.reverse(state.accumulated_audio)

      # Enviar al GenServer
      send(state.controller_pid, {:audio_chunk, buffers, state.stream_format})
    end
  end
end
