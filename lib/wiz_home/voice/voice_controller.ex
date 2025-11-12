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
      state = %{
        api_key: api_key,
        light_ips: light_ips,
        processing: false,
        pending_chunks: []
      }

      Logger.info("VoiceController iniciado con #{length(light_ips)} luz(es) configurada(s)")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:audio_chunk, buffers, stream_format}, state) do
    # Si ya hay un procesamiento en curso, agregar a la cola
    if state.processing do
      Logger.debug("Chunk en cola (procesamiento en curso). Cola: #{length(state.pending_chunks) + 1}")
      new_state = %{state | pending_chunks: state.pending_chunks ++ [{buffers, stream_format}]}
      {:noreply, new_state}
    else
      # Procesar inmediatamente
      new_state = %{state | processing: true}

      # Procesar de forma asíncrona
      Task.start(fn ->
        process_audio_chunk(buffers, stream_format, state)

        # Notificar que terminó el procesamiento
        GenServer.cast(__MODULE__, :processing_complete)
      end)

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Mensaje no reconocido: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:processing_complete, state) do
    # Procesar el siguiente chunk de la cola si hay alguno
    case state.pending_chunks do
      [] ->
        # No hay chunks pendientes, solo marcar como no procesando
        {:noreply, %{state | processing: false}}

      [{buffers, stream_format} | rest] ->
        # Hay chunks pendientes, procesar el siguiente
        Logger.debug("Procesando chunk de la cola. Quedan #{length(rest)} en cola")

        Task.start(fn ->
          process_audio_chunk(buffers, stream_format, state)
          GenServer.cast(__MODULE__, :processing_complete)
        end)

        new_state = %{
          state
          | processing: true,
            pending_chunks: rest
        }

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:update_light_ips, light_ips}, state) do
    Logger.info("IPs de luces actualizadas: #{inspect(light_ips)}")
    {:noreply, %{state | light_ips: light_ips}}
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
