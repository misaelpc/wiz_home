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
      debounce_ms = Keyword.get(opts, :debounce_ms, 1000) # Debounce de 1 segundo entre comandos

      state = %{
        api_key: api_key,
        light_ips: light_ips,
        pending_chunks: [],
        batch_size: batch_size,
        batch_timeout_ms: batch_timeout_ms,
        batch_timer: nil,
        last_command_time: 0,
        debounce_ms: debounce_ms
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

    # Si alcanzamos el tamaño del batch, procesar inmediatamente en paralelo
    if length(new_pending) >= state.batch_size do
      process_batch_parallel(new_state)
    else
      Logger.debug("Chunk acumulado. Total: #{length(new_pending)}/#{state.batch_size}")
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:process_batch_timeout, state) do
    # Timeout alcanzado, procesar chunks acumulados si hay alguno
    if length(state.pending_chunks) > 0 do
      process_batch_parallel(state)
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
  def handle_cast({:execute_command, command, affected_ips, command_time}, state) do
    # Verificar debounce
    time_since_last_command = command_time - state.last_command_time

    if time_since_last_command >= state.debounce_ms do
      # Ejecutar comando
      execute_command_action(command, affected_ips)
      Logger.info("Comando ejecutado: #{command} en #{length(affected_ips)} foco(s)")
      {:noreply, %{state | last_command_time: command_time}}
    else
      Logger.debug("Comando ignorado por debounce (#{time_since_last_command}ms < #{state.debounce_ms}ms)")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_light_ips, light_ips}, state) do
    Logger.info("IPs de luces actualizadas: #{inspect(light_ips)}")
    {:noreply, %{state | light_ips: light_ips}}
  end

  # Procesa chunks en paralelo usando Task.async_stream
  defp process_batch_parallel(state) when length(state.pending_chunks) == 0 do
    {:noreply, state}
  end

  defp process_batch_parallel(state) do
    # Cancelar timer si existe
    if state.batch_timer do
      Process.cancel_timer(state.batch_timer)
    end

    # Tomar todos los chunks acumulados
    chunks_to_process = state.pending_chunks

    Logger.info("Procesando #{length(chunks_to_process)} chunk(s) en paralelo")

    # Procesar cada chunk en paralelo usando Task.async_stream
    chunks_to_process
    |> Task.async_stream(
      fn {buffers, stream_format} ->
        # Transcribir y procesar comando, retornar resultado
        transcribe_and_process(buffers, stream_format, state)
      end,
      max_concurrency: 5, # Procesar hasta 5 chunks en paralelo
      timeout: 30_000, # Timeout de 30 segundos por chunk
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {:command, command, affected_ips}} ->
        # Verificar debounce antes de ejecutar
        current_time = System.system_time(:millisecond)
        GenServer.cast(__MODULE__, {:execute_command, command, affected_ips, current_time})

      {:ok, :no_command} ->
        :ok

      {:ok, {:error, reason}} ->
        Logger.error("Error procesando chunk: #{inspect(reason)}")

      {:error, reason} ->
        Logger.error("Error procesando chunk en paralelo: #{inspect(reason)}")
    end)

    # Limpiar chunks procesados
    new_state = %{
      state
      | pending_chunks: [],
        batch_timer: nil
    }

    {:noreply, new_state}
  end

  # Transcribe y procesa comando (llamado desde Task.async_stream)
  defp transcribe_and_process(buffers, stream_format, state) do
    Logger.debug("Procesando chunk de audio (#{length(buffers)} buffers)")

    case WizHome.Voice.WhisperClient.transcribe(buffers, stream_format, state.api_key) do
      {:ok, text} ->
        Logger.info("Transcripción: #{text}")

        # Procesar comando usando LLM (con regex como fallback)
        case WizHome.Voice.CommandProcessor.process(text, state.light_ips, state.api_key) do
          {:ok, command, affected_ips} ->
            {:command, command, affected_ips}

          :no_command ->
            :no_command
        end

      {:error, reason} ->
        Logger.error("Error en transcripción: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Ejecuta la acción del comando
  defp execute_command_action(:turn_on, light_ips) do
    Enum.each(light_ips, fn ip ->
      case WizHome.set_state(ip, true) do
        {:ok, _} -> Logger.info("Luz prendida: #{ip}")
        {:error, reason} -> Logger.error("Error al prender luz #{ip}: #{inspect(reason)}")
      end
    end)
  end

  defp execute_command_action(:turn_off, light_ips) do
    Enum.each(light_ips, fn ip ->
      case WizHome.set_state(ip, false) do
        {:ok, _} -> Logger.info("Luz apagada: #{ip}")
        {:error, reason} -> Logger.error("Error al apagar luz #{ip}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Actualiza las IPs de las luces a controlar.
  """
  def update_light_ips(light_ips) when is_list(light_ips) do
    GenServer.cast(__MODULE__, {:update_light_ips, light_ips})
  end
end
