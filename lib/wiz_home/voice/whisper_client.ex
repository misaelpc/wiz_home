defmodule WizHome.Voice.WhisperClient do
  @moduledoc """
  Cliente para comunicarse con OpenAI Whisper API.

  Convierte buffers de audio PCM a formato WAV y los envía a la API para transcripción.
  """

  require Logger

  @whisper_api_url "https://api.openai.com/v1/audio/transcriptions"

  @doc """
  Transcribe audio desde buffers PCM usando OpenAI Whisper API.

  ## Parámetros
  - `buffers`: Lista de buffers de audio en formato PCM
  - `stream_format`: Formato del stream (RawAudio) con sample_rate y channels
  - `api_key`: Clave de API de OpenAI

  ## Retorna
  - `{:ok, text}` - Texto transcrito
  - `{:error, reason}` - Error en la transcripción
  """
  def transcribe(buffers, stream_format, api_key) when is_list(buffers) and length(buffers) > 0 do
    case convert_buffers_to_wav(buffers, stream_format) do
      {:ok, wav_data} ->
        send_to_whisper_api(wav_data, api_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def transcribe(_buffers, _stream_format, _api_key) do
    {:error, :empty_buffers}
  end

  # Convierte buffers PCM a formato WAV
  defp convert_buffers_to_wav(buffers, %{sample_rate: sample_rate, channels: channels}) do
    try do
      # Concatenar todos los payloads de los buffers
      pcm_data =
        buffers
        |> Enum.map(& &1.payload)
        |> Enum.reduce(<<>>, fn payload, acc -> <<acc::binary, payload::binary>> end)

      # Crear header WAV
      wav_header = create_wav_header(pcm_data, sample_rate, channels)

      # Combinar header + datos PCM
      wav_data = <<wav_header::binary, pcm_data::binary>>

      {:ok, wav_data}
    rescue
      e -> {:error, {:conversion_error, e}}
    end
  end

  defp convert_buffers_to_wav(_buffers, _stream_format) do
    {:error, :invalid_stream_format}
  end

  # Crea el header WAV para audio PCM s16le
  defp create_wav_header(pcm_data, sample_rate, channels) do
    data_size = byte_size(pcm_data)
    file_size = 36 + data_size

    # RIFF header
    riff_chunk_id = "RIFF"
    riff_chunk_size = file_size - 8
    riff_format = "WAVE"

    # Format chunk
    fmt_chunk_id = "fmt "
    fmt_chunk_size = 16
    audio_format = 1  # PCM
    bits_per_sample = 16
    byte_rate = sample_rate * channels * div(bits_per_sample, 8)
    block_align = channels * div(bits_per_sample, 8)

    # Data chunk
    data_chunk_id = "data"
    data_chunk_size = data_size

    <<
      riff_chunk_id::binary-size(4),
      riff_chunk_size::little-32,
      riff_format::binary-size(4),
      fmt_chunk_id::binary-size(4),
      fmt_chunk_size::little-32,
      audio_format::little-16,
      channels::little-16,
      sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      bits_per_sample::little-16,
      data_chunk_id::binary-size(4),
      data_chunk_size::little-32
    >>
  end

  # Envía datos WAV a OpenAI Whisper API
  defp send_to_whisper_api(wav_data, api_key) do
    boundary = generate_boundary()

    # Construir el cuerpo multipart correctamente con datos binarios
    body_parts = [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n",
      "Content-Type: audio/wav\r\n\r\n",
      wav_data,
      "\r\n--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"model\"\r\n\r\n",
      "whisper-1\r\n",
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"language\"\r\n\r\n",
      "es\r\n",
      "--#{boundary}--\r\n"
    ]

    body = IO.iodata_to_binary(body_parts)

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "multipart/form-data; boundary=#{boundary}"}
    ]

    case Finch.build(:post, @whisper_api_url, headers, body) |> Finch.request(WizHome.Finch) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"text" => text}} ->
            Logger.info("Whisper transcription: #{text}")
            {:ok, String.trim(text)}

          {:ok, json} ->
            Logger.warning("Unexpected Whisper response format: #{inspect(json)}")
            {:error, :unexpected_response_format}

          {:error, reason} ->
            Logger.error("Failed to parse Whisper response: #{inspect(reason)}")
            {:error, {:parse_error, reason}}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Whisper API error: status=#{status}, body=#{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Whisper API request failed: #{inspect(reason)}")
        {:error, {:request_error, reason}}
    end
  end

  # Genera un boundary único para multipart
  defp generate_boundary do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.downcase()
  end
end
