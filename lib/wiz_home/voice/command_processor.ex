defmodule WizHome.Voice.CommandProcessor do
  @moduledoc """
  Procesa texto transcrito y detecta comandos de voz para controlar las luces.

  Detecta comandos como:
  - "apaga las luces" / "apaga la luz"
  - "prende las luces" / "prende la luz" / "enciende las luces"
  """

  require Logger

  @turn_off_patterns ~r/(apaga|apagar|apágame|apágala|apágalas)\s*(las?\s*)?(luz|luces|bombilla|bombillas)/i
  @turn_on_patterns ~r/(prende|prender|enciende|encender|enciéndeme|enciéndela|enciéndelas)\s*(las?\s*)?(luz|luces|bombilla|bombillas)/i

  @doc """
  Procesa texto transcrito y detecta comandos.

  ## Parámetros
  - `text`: Texto transcrito del audio
  - `light_ips`: Lista de IPs de las luces a controlar

  ## Retorna
  - `{:ok, :turn_off}` - Comando para apagar luces
  - `{:ok, :turn_on}` - Comando para prender luces
  - `:no_command` - No se detectó ningún comando
  """
  def process(text, light_ips) when is_binary(text) and is_list(light_ips) do
    normalized_text = String.downcase(String.trim(text))

    cond do
      Regex.match?(@turn_off_patterns, normalized_text) ->
        Logger.info("Comando detectado: APAGAR luces")
        execute_command(:turn_off, light_ips)
        {:ok, :turn_off}

      Regex.match?(@turn_on_patterns, normalized_text) ->
        Logger.info("Comando detectado: PRENDER luces")
        execute_command(:turn_on, light_ips)
        {:ok, :turn_on}

      true ->
        Logger.debug("No se detectó comando en: #{text}")
        :no_command
    end
  end

  def process(_text, _light_ips) do
    :no_command
  end

  # Ejecuta el comando en todas las luces configuradas
  defp execute_command(:turn_off, light_ips) do
    Enum.each(light_ips, fn ip ->
      case WizHome.set_state(ip, false) do
        {:ok, _} ->
          Logger.info("Luz apagada: #{ip}")

        {:error, reason} ->
          Logger.error("Error al apagar luz #{ip}: #{inspect(reason)}")
      end
    end)
  end

  defp execute_command(:turn_on, light_ips) do
    Enum.each(light_ips, fn ip ->
      case WizHome.set_state(ip, true) do
        {:ok, _} ->
          Logger.info("Luz prendida: #{ip}")

        {:error, reason} ->
          Logger.error("Error al prender luz #{ip}: #{inspect(reason)}")
      end
    end)
  end
end
