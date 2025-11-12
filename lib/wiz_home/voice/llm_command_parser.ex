defmodule WizHome.Voice.LLMCommandParser do
  @moduledoc """
  Usa un LLM (OpenAI GPT) para interpretar comandos de voz y extraer la intención.

  En lugar de usar regex, envía el texto transcrito a GPT para que determine:
  - La acción (apagar/prender)
  - Qué focos controlar (todos o específicos)
  """

  require Logger

  @gpt_api_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Analiza el texto usando un LLM para extraer el comando de control de luces.

  ## Parámetros
  - `text`: Texto transcrito del audio
  - `light_ips`: Lista de IPs de las luces disponibles
  - `api_key`: Clave de API de OpenAI

  ## Retorna
  - `{:ok, action, affected_ips}` - Comando detectado
    - `action`: `:turn_on` o `:turn_off`
    - `affected_ips`: Lista de IPs a controlar
  - `{:error, reason}` - Error en el análisis
  - `:no_command` - No se detectó un comando de control de luces
  """
  def parse_command(text, light_ips, api_key) when is_binary(text) and is_list(light_ips) do
    prompt = build_prompt(text, light_ips)

    case call_gpt_api(prompt, api_key) do
      {:ok, response_text} ->
        parse_llm_response(response_text, light_ips)

      {:error, reason} ->
        Logger.error("Error al llamar a GPT: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Construye el prompt para el LLM
  defp build_prompt(text, light_ips) do
    focos_list =
      light_ips
      |> Enum.with_index(1)
      |> Enum.map(fn {ip, index} -> "Foco #{index}: #{ip}" end)
      |> Enum.join("\n")

    """
    Eres un asistente que interpreta comandos de voz para controlar luces inteligentes.

    Focos disponibles:
    #{focos_list}

    Analiza el siguiente texto transcrito y determina si es un comando para controlar las luces.
    El texto puede tener errores de transcripción, signos de exclamación, o variaciones en las palabras.
    Debes interpretar la INTENCIÓN del usuario, no solo buscar palabras exactas.

    Si es un comando, responde SOLO con un JSON válido en este formato exacto:
    {
      "action": "turn_on" o "turn_off",
      "focos": [1, 2] o "all"
    }

    Si NO es un comando de luces, responde con:
    {"action": null}

    Ejemplos de comandos válidos (incluyendo variaciones):
    - "apaga las luces" → {"action": "turn_off", "focos": "all"}
    - "¡Prendan las luces!" → {"action": "turn_on", "focos": "all"}  (variación de "prende")
    - "prende el foco 1" → {"action": "turn_on", "focos": [1]}
    - "enciende todas las luces" → {"action": "turn_on", "focos": "all"}
    - "apaga el segundo foco" → {"action": "turn_off", "focos": [2]}
    - "prendan el foco uno" → {"action": "turn_on", "focos": [1]}
    - "apágame las luces" → {"action": "turn_off", "focos": "all"}
    - "hola cómo estás" → {"action": null}
    - "Subtítulos realizados por la comunidad" → {"action": null}

    Palabras clave para reconocer:
    - Apagar: apaga, apagar, apágame, apágala, apágalas, apaguen
    - Prender: prende, prender, prendan, enciende, encender, enciéndeme, enciéndela, enciéndelas
    - Todas las luces: todas, todas las luces, las luces, la luz
    - Foco específico: foco 1, foco 2, primer foco, segundo foco, foco uno, foco dos

    Texto a analizar: "#{text}"

    Responde SOLO con el JSON, sin texto adicional, sin markdown, sin explicaciones.
    """
  end

  # Llama a la API de OpenAI GPT
  defp call_gpt_api(prompt, api_key) do
    body = Jason.encode!(%{
      model: "gpt-4o-mini",
      messages: [
        %{
          role: "system",
          content: "Eres un asistente que analiza comandos de voz y responde SOLO con JSON válido."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.1,
      max_tokens: 150
    })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Finch.build(:post, @gpt_api_url, headers, body) |> Finch.request(WizHome.Finch) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, String.trim(content)}

          {:ok, json} ->
            Logger.warning("Respuesta inesperada de GPT: #{inspect(json)}")
            {:error, :unexpected_response_format}

          {:error, reason} ->
            Logger.error("Error al parsear respuesta de GPT: #{inspect(reason)}")
            {:error, {:parse_error, reason}}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("GPT API error: status=#{status}, body=#{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("GPT API request failed: #{inspect(reason)}")
        {:error, {:request_error, reason}}
    end
  end

  # Parsea la respuesta del LLM
  defp parse_llm_response(response_text, light_ips) do
    # Limpiar el texto (puede tener markdown code blocks)
    cleaned_text =
      response_text
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned_text) do
      {:ok, %{"action" => nil}} ->
        :no_command

      {:ok, %{"action" => action, "focos" => focos}} when action in ["turn_on", "turn_off"] ->
        action_atom = if action == "turn_on", do: :turn_on, else: :turn_off

        affected_ips = case focos do
          "all" ->
            light_ips

          focos_list when is_list(focos_list) ->
            focos_list
            |> Enum.map(&normalize_foco_number/1)
            |> Enum.filter(fn idx -> idx >= 1 and idx <= length(light_ips) end)
            |> Enum.map(fn idx -> Enum.at(light_ips, idx - 1) end)

          _ ->
            []
        end

        if length(affected_ips) > 0 do
          Logger.info("LLM detectó comando: #{action} en focos #{inspect(affected_ips)}")
          {:ok, action_atom, affected_ips}
        else
          Logger.warning("LLM detectó comando pero no hay focos válidos")
          :no_command
        end

      {:ok, json} ->
        Logger.warning("Formato de respuesta LLM inesperado: #{inspect(json)}")
        :no_command

      {:error, reason} ->
        Logger.error("Error al parsear respuesta LLM: #{inspect(reason)}, texto: #{cleaned_text}")
        :no_command
    end
  end

  # Normaliza números de focos (puede venir como string o integer)
  defp normalize_foco_number(num) when is_integer(num), do: num
  defp normalize_foco_number(num) when is_binary(num) do
    case Integer.parse(num) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp normalize_foco_number(_), do: 0
end
