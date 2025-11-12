defmodule WizHome do
  @moduledoc """
  WizHome keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  @port 38_899

  # Encender / apagar
  def set_state(ip, state) when is_boolean(state) do
    cmd = %{
      id: 1,
      method: "setState",
      params: %{state: state}
    }

    send_cmd(ip, cmd)
  end

  # RGB: {r, g, b} 0-255, brillo 10-100
  def set_rgb(ip, {r, g, b}, dimming \\ 75) do
    cmd = %{
      id: 1,
      method: "setPilot",
      params: %{
        r: r,
        g: g,
        b: b,
        dimming: dimming
      }
    }

    send_cmd(ip, cmd)
  end

  # Temperatura en Kelvin (2200-6200), brillo 10-100
  def set_temp(ip, temp, dimming \\ 75) do
    cmd = %{
      id: 1,
      method: "setPilot",
      params: %{
        temp: temp,
        dimming: dimming
      }
    }

    send_cmd(ip, cmd)
  end

  # Escena por ID (usa el mismo mapping que SCENE_IDS del repo de Adafruit si quieres)
  def set_scene(ip, scene_id, dimming \\ 75, speed \\ 175) do
    cmd = %{
      id: 1,
      method: "setPilot",
      params: %{
        sceneId: scene_id,
        dimming: dimming,
        speed: speed
      }
    }

    send_cmd(ip, cmd)
  end

  # Obtener estado actual (getPilot)
  def get_status(ip) do
    cmd = %{
      method: "getPilot",
      params: %{}
    }

    send_cmd(ip, cmd)
  end

  # --- Audio Recording ---

  @doc """
  Lista los dispositivos de audio disponibles usando PortAudio.
  Útil para encontrar el device_id de tu micrófono USB.
  """
  def list_audio_devices do
    Membrane.PortAudio.print_devices()
  end

  @doc """
  Inicia la grabación de audio desde el micrófono especificado.

  ## Parámetros
  - `device_id`: ID del dispositivo (entero) o `:default` para el dispositivo por defecto.
                 Usa `list_audio_devices/0` para encontrar el ID correcto.
  - `output_file`: Ruta del archivo WAV donde se guardará la grabación (default: "capture.wav")
  - `channels`: Número de canales (1=mono, 2=estéreo). Si es `nil`, usa el valor por defecto del dispositivo.
  - `sample_rate`: Frecuencia de muestreo (ej: 44100, 16000). Si es `nil`, usa el valor por defecto del dispositivo.

  ## Ejemplo
      # Usar dispositivo por defecto con valores por defecto del dispositivo
      WizHome.start_recording()

      # Usar dispositivo específico
      WizHome.start_recording(device_id: 0, output_file: "mi_grabacion.wav")

      # Especificar parámetros personalizados
      WizHome.start_recording(device_id: 0, channels: 1, sample_rate: 16000)
  """
  def start_recording(opts \\ []) do
    case Membrane.Pipeline.start_link(WizHome.MicToWav, opts) do
      {:ok, pid, _supervisor_pid} ->
        IO.puts("🎤 Grabación iniciada. Presiona Ctrl+C para detener.")
        {:ok, pid}

      {:error, reason} ->
        IO.puts("❌ Error al iniciar la grabación: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Detiene la grabación de audio.
  """
  def stop_recording(pid) when is_pid(pid) do
    GenServer.stop(pid)
  end

  # --- Voice Control ---

  @doc """
  Inicia el sistema de control por voz.

  ## Parámetros
  - `device_id`: ID del dispositivo de audio (entero) o `:default`
  - `light_ips`: Lista de IPs de las luces a controlar (requerido)
  - `api_key`: Clave de API de OpenAI (opcional, puede venir de config)
  - `chunk_duration_ms`: Duración de chunks de audio en ms (default: 3000)
  - `debug_output`: Ruta opcional para guardar audio WAV para debug

  ## Ejemplo
      # Iniciar con una luz
      WizHome.start_voice_control(light_ips: ["192.168.1.100"])

      # Iniciar con múltiples luces y dispositivo específico
      WizHome.start_voice_control(
        device_id: 0,
        light_ips: ["192.168.1.100", "192.168.1.101"],
        chunk_duration_ms: 2000
      )
  """
  def start_voice_control(opts) do
    light_ips = Keyword.get(opts, :light_ips, [])

    if length(light_ips) == 0 do
      {:error, :no_light_ips}
    else
      # Iniciar VoiceController
      controller_opts = [
        api_key: Keyword.get(opts, :api_key),
        light_ips: light_ips
      ]

      case WizHome.Voice.VoiceController.start_link(controller_opts) do
        {:ok, controller_pid} ->
          # Iniciar pipeline de voz
          pipeline_opts = [
            device_id: Keyword.get(opts, :device_id, :default),
            controller_pid: controller_pid,
            channels: Keyword.get(opts, :channels),
            sample_rate: Keyword.get(opts, :sample_rate),
            chunk_duration_ms: Keyword.get(opts, :chunk_duration_ms, 3000),
            debug_output: Keyword.get(opts, :debug_output)
          ]

          case Membrane.Pipeline.start_link(WizHome.Voice.VoicePipeline, pipeline_opts) do
            {:ok, pipeline_pid, _supervisor_pid} ->
              IO.puts("🎤 Control por voz iniciado con #{length(light_ips)} foco(s)")
              IO.puts("   Comandos disponibles:")
              IO.puts("   - 'apaga las luces' / 'prende las luces' (todos los focos)")
              IO.puts("   - 'apaga el foco 1' / 'prende el foco 1' (foco específico)")
              {:ok, pipeline_pid, controller_pid}

            {:error, reason} ->
              # Detener controller si el pipeline falla
              GenServer.stop(controller_pid)
              IO.puts("❌ Error al iniciar pipeline de voz: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          IO.puts("❌ Error al iniciar VoiceController: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Detiene el sistema de control por voz.

  ## Parámetros
  - `pipeline_pid`: PID del pipeline (retornado por start_voice_control)
  - `controller_pid`: PID del controller (retornado por start_voice_control)
  """
  def stop_voice_control(pipeline_pid, controller_pid) when is_pid(pipeline_pid) and is_pid(controller_pid) do
    GenServer.stop(pipeline_pid)
    GenServer.stop(controller_pid)
    IO.puts("🛑 Control por voz detenido")
    :ok
  end

  @doc """
  Actualiza las IPs de las luces a controlar.

  ## Parámetros
  - `light_ips`: Lista de IPs de las luces
  """
  def configure_lights(light_ips) when is_list(light_ips) do
    case WizHome.Voice.VoiceController.get_pid() do
      {:ok, _pid} ->
        WizHome.Voice.VoiceController.update_light_ips(light_ips)
        IO.puts("✅ IPs de luces actualizadas: #{inspect(light_ips)}")
        :ok

      {:error, :not_started} ->
        {:error, :controller_not_started}
    end
  end

  # --- Internals ---

  defp send_cmd(ip, cmd) do
    {:ok, socket} =
      :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true}])

    payload = Jason.encode!(cmd)

    :ok =
      :gen_udp.send(
        socket,
        String.to_charlist(ip),
        @port,
        payload
      )

    resp =
      case :gen_udp.recv(socket, 0, 3_000) do
        {:ok, {_resp_ip, _resp_port, data}} ->
          case Jason.decode(data) do
            {:ok, json} -> {:ok, json}
            _ -> {:ok, data}
          end

        {:error, :timeout} ->
          {:error, :timeout}
      end

    :gen_udp.close(socket)
    resp
  end
end
