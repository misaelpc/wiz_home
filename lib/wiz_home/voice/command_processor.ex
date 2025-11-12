defmodule WizHome.Voice.CommandProcessor do
  @moduledoc """
  Procesa texto transcrito y detecta comandos de voz para controlar las luces.

  Detecta comandos como:
  - "apaga las luces" / "apaga la luz" / "apaga todas las luces" (controla todos los focos)
  - "apaga el foco 1" / "apaga el primer foco" (controla foco específico)
  - "prende las luces" / "prende la luz" / "enciende las luces"
  - "prende el foco 1" / "prende el primer foco"
  """

  require Logger

  # Patrones para apagar/prender todas las luces
  @turn_off_all_patterns ~r/(apaga|apagar|apágame|apágala|apágalas)\s*(las?\s*)?(todas?\s*)?(luz|luces|bombilla|bombillas)/i
  @turn_on_all_patterns ~r/(prende|prender|enciende|encender|enciéndeme|enciéndela|enciéndelas)\s*(las?\s*)?(todas?\s*)?(luz|luces|bombilla|bombillas)/i

  # Patrones para controlar focos específicos (foco 1, primer foco, etc.)
  @turn_off_specific_patterns ~r/(apaga|apagar)\s*(el\s*)?(foco|focos|bombilla|bombillas|luce?)\s*(\d+|primero|segundo|tercero|cuarto|quinto|uno|dos|tres|cuatro|cinco)/i
  @turn_on_specific_patterns ~r/(prende|prender|enciende|encender)\s*(el\s*)?(foco|focos|bombilla|bombillas|luce?)\s*(\d+|primero|segundo|tercero|cuarto|quinto|uno|dos|tres|cuatro|cinco)/i

  @doc """
  Procesa texto transcrito y detecta comandos.

  ## Parámetros
  - `text`: Texto transcrito del audio
  - `light_ips`: Lista de IPs de las luces a controlar (ordenadas: [foco1_ip, foco2_ip, ...])

  ## Retorna
  - `{:ok, :turn_off, ips}` - Comando para apagar luces específicas
  - `{:ok, :turn_on, ips}` - Comando para prender luces específicas
  - `:no_command` - No se detectó ningún comando
  """
  def process(text, light_ips) when is_binary(text) and is_list(light_ips) do
    normalized_text = String.downcase(String.trim(text))

    cond do
      # Comando para apagar todas las luces
      Regex.match?(@turn_off_all_patterns, normalized_text) ->
        Logger.info("Comando detectado: APAGAR todas las luces")
        execute_command(:turn_off, light_ips)
        {:ok, :turn_off, light_ips}

      # Comando para prender todas las luces
      Regex.match?(@turn_on_all_patterns, normalized_text) ->
        Logger.info("Comando detectado: PRENDER todas las luces")
        execute_command(:turn_on, light_ips)
        {:ok, :turn_on, light_ips}

      # Comando para apagar foco específico
      Regex.match?(@turn_off_specific_patterns, normalized_text) ->
        case extract_foco_number(normalized_text, length(light_ips)) do
          {:ok, foco_index} when foco_index > 0 and foco_index <= length(light_ips) ->
            ip = Enum.at(light_ips, foco_index - 1)
            Logger.info("Comando detectado: APAGAR foco #{foco_index} (#{ip})")
            execute_command(:turn_off, [ip])
            {:ok, :turn_off, [ip]}

          _ ->
            Logger.warning("Foco no encontrado en comando: #{text}")
            :no_command
        end

      # Comando para prender foco específico
      Regex.match?(@turn_on_specific_patterns, normalized_text) ->
        case extract_foco_number(normalized_text, length(light_ips)) do
          {:ok, foco_index} when foco_index > 0 and foco_index <= length(light_ips) ->
            ip = Enum.at(light_ips, foco_index - 1)
            Logger.info("Comando detectado: PRENDER foco #{foco_index} (#{ip})")
            execute_command(:turn_on, [ip])
            {:ok, :turn_on, [ip]}

          _ ->
            Logger.warning("Foco no encontrado en comando: #{text}")
            :no_command
        end

      true ->
        Logger.debug("No se detectó comando en: #{text}")
        :no_command
    end
  end

  def process(_text, _light_ips) do
    :no_command
  end

  # Extrae el número del foco del texto
  defp extract_foco_number(text, max_focos) do
    # Buscar números (1, 2, 3, etc.)
    case Regex.run(~r/(\d+)/, text) do
      [_, num_str] ->
        num = String.to_integer(num_str)
        if num >= 1 and num <= max_focos do
          {:ok, num}
        else
          {:error, :foco_invalido}
        end

      _ ->
        # Buscar palabras (primero, segundo, uno, dos, etc.)
        extract_foco_from_words(text, max_focos)
    end
  end

  # Extrae el número del foco de palabras en español
  defp extract_foco_from_words(text, _max_focos) do
    word_to_number = %{
      "primero" => 1,
      "segundo" => 2,
      "tercero" => 3,
      "cuarto" => 4,
      "quinto" => 5,
      "uno" => 1,
      "dos" => 2,
      "tres" => 3,
      "cuatro" => 4,
      "cinco" => 5
    }

    Enum.find_value(word_to_number, fn {word, num} ->
      if String.contains?(text, word), do: {:ok, num}, else: nil
    end) || {:error, :foco_no_encontrado}
  end

  # Ejecuta el comando en las luces especificadas
  defp execute_command(:turn_off, light_ips) when is_list(light_ips) do
    Enum.each(light_ips, fn ip ->
      case WizHome.set_state(ip, false) do
        {:ok, _} ->
          Logger.info("Luz apagada: #{ip}")

        {:error, reason} ->
          Logger.error("Error al apagar luz #{ip}: #{inspect(reason)}")
      end
    end)
  end

  defp execute_command(:turn_on, light_ips) when is_list(light_ips) do
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
