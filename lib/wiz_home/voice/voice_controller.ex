defmodule WizHome.Voice.VoiceController do
  @moduledoc """
  GenServer que orquesta el procesamiento de audio en tiempo real.

  Recibe chunks de audio del AudioChunkFilter, los envía a Whisper API,
  y procesa los comandos detectados.
  """

  use GenServer

  require Logger

  @doc """
  Inicia el VoiceController.

  ## Opciones
  - `api_key`: Clave de API de OpenAI (requerida)
  - `light_ips`: Lista de IPs de las luces a controlar (requerida)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Obtiene el PID del VoiceController.
  """
  def get_pid do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> {:ok, pid}
    end
  end

  # Callbacks de GenServer

  @impl true
  def init(opts) do
    api_key = Keyword.get(opts, :api_key) || Application.get_env(:wiz_home, :openai_api_key)
    light_ips = Keyword.get(opts, :light_ips, [])

    if is_nil(api_key) do
      Logger.error("OpenAI API key no configurada")
      {:stop, :missing_api_key}
    else
      # Configuración: acumular chunks antes de procesar
      batch_size = Keyword.get(opts, :batch_size, 2) # Procesar cada 2 chunks
      batch_timeout_ms = Keyword.get(opts, :batch_timeout_ms, 2000) # O después de 2 segundos

      state = %{
        api_key: api_key,
        light_ips: light_ips,
        processing: false,
        pending_chunks: [],
        batch_size: batch_size,
        batch_timeout_ms: batch_timeout_ms,
        batch_timer: nil
      }

      Logger.info("VoiceController iniciado con #{length(light_ips)} luz(es) configurada(s)")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:audio_chunk, buffers, stream_format}, state) do
    # Agregar chunk a la cola
    new_pending = state.pending_chunks ++ [{buffers, stream_format}]

    # Cancelar timer anterior si existe
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    # Programar timer para procesar después del timeout
    timer = Process.send_after(self(), :process_batch_timeout, state.batch_timeout_ms)

    new_state = %{state | pending_chunks: new_pending, batch_timer: timer}

    # Si alcanzamos el tamaño del batch y no estamos procesando, procesar inmediatamente
    if length(new_pending) >= state.batch_size and not state.processing do
      process_batch(new_state)
    else
      Logger.debug("Chunk acumulado. Total: #{length(new_pending)}/#{state.batch_size}")
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:process_batch_timeout, state) do
    # Timeout alcanzado, procesar chunks acumulados si hay alguno
    if length(state.pending_chunks) > 0 and not state.processing do
      process_batch(state)
    else
      {:noreply, %{state | batch_timer: nil}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Mensaje no reconocido: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:processing_complete, state) do
    # Marcar como no procesando
    new_state = %{state | processing: false}

    # Si hay chunks pendientes, procesar el siguiente batch
    if length(new_state.pending_chunks) > 0 do
      process_batch(new_state)
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:update_light_ips, light_ips}, state) do
    Logger.info("IPs de luces actualizadas: #{inspect(light_ips)}")
    {:noreply, %{state | light_ips: light_ips}}
  end

  # Procesa un batch de chunks acumulados
  defp process_batch(state) when length(state.pending_chunks) == 0 do
    {:noreply, state}
  end

  defp process_batch(state) do
    # Cancelar timer si existe
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    # Tomar todos los chunks acumulados
    chunks_to_process = state.pending_chunks
    remaining_chunks = []

    Logger.debug("Procesando batch de #{length(chunks_to_process)} chunk(s)")

    # Combinar todos los chunks en uno solo
    {combined_buffers, stream_format} = combine_chunks(chunks_to_process)

    # Procesar de forma asíncrona
    Task.start(fn ->
      process_audio_chunk(combined_buffers, stream_format, state)
      GenServer.cast(__MODULE__, :processing_complete)
    end)

    new_state = %{
      state
      | processing: true,
        pending_chunks: remaining_chunks,
        batch_timer: nil
    }

    {:noreply, new_state}
  end

  # Combina múltiples chunks en uno solo
  defp combine_chunks(chunks) when length(chunks) > 0 do
    # Todos los chunks deberían tener el mismo stream_format
    {_buffers, stream_format} = List.first(chunks)

    # Combinar todos los buffers de todos los chunks
    combined_buffers =
      chunks
      |> Enum.flat_map(fn {buffers, _format} -> buffers end)

    {combined_buffers, stream_format}
  end

  # Procesa un chunk de audio
  defp process_audio_chunk(buffers, stream_format, state) do
    Logger.debug("Procesando chunk de audio (#{length(buffers)} buffers)")

    case WizHome.Voice.WhisperClient.transcribe(buffers, stream_format, state.api_key) do
      {:ok, text} ->
        Logger.info("Transcripción: #{text}")

        # Procesar comando usando LLM (con regex como fallback)
        case WizHome.Voice.CommandProcessor.process(text, state.light_ips, state.api_key) do
          {:ok, command, affected_ips} ->
            Logger.info("Comando ejecutado: #{command} en #{length(affected_ips)} foco(s)")

          :no_command ->
            Logger.debug("No se detectó comando")
        end

      {:error, reason} ->
        Logger.error("Error en transcripción: #{inspect(reason)}")
    end
  end

  @doc """
  Actualiza las IPs de las luces a controlar.
  """
  def update_light_ips(light_ips) when is_list(light_ips) do
    GenServer.cast(__MODULE__, {:update_light_ips, light_ips})
  end
end
