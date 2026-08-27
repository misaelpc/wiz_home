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

  # Brightness only (10-100). Sending RGB at the same time can make Wiz
  # bulbs ignore dimming, so slider changes use this command.
  def set_dimming(ip, dimming) when is_integer(dimming) and dimming >= 10 and dimming <= 100 do
    cmd = %{
      id: 1,
      method: "setPilot",
      params: %{
        state: true,
        dimming: dimming
      }
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

  # --- Internals ---

  defp send_cmd(ip, cmd) do
    case :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true}]) do
      {:ok, socket} ->
        payload = Jason.encode!(cmd)

        resp =
          case :gen_udp.send(
                 socket,
                 String.to_charlist(ip),
                 @port,
                 payload
               ) do
            :ok ->
              case :gen_udp.recv(socket, 0, 3_000) do
                {:ok, {_resp_ip, _resp_port, data}} ->
                  case Jason.decode(data) do
                    {:ok, json} -> {:ok, json}
                    _ -> {:ok, data}
                  end

                {:error, :timeout} ->
                  {:error, :timeout}

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end

        :gen_udp.close(socket)
        resp

      {:error, reason} ->
        {:error, reason}
    end
  end
end
