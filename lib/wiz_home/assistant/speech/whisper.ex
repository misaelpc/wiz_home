defmodule WizHome.Assistant.Speech.Whisper do
  @moduledoc """
  Speech-to-text via a compiled whisper.cpp `whisper-cli` binary.

  Shells out rather than binding via NIF, matching how whisper.cpp is meant to
  be used (a standalone CLI over a WAV file) and keeping the Rust toolchain
  reserved for the Ortex/ONNX side of this project.
  """

  require Logger

  @doc """
  Transcribes a 16 kHz mono WAV file.

  Returns `{:ok, text}` (empty string if nothing was heard) or `{:error, reason}`.
  """
  def transcribe(wav_path, opts \\ []) when is_binary(wav_path) do
    cli = Keyword.get(opts, :cli_path, default_path(:whisper_cli_relpath))
    model = Keyword.get(opts, :model_path, default_path(:whisper_model_relpath))
    lang = Keyword.get(opts, :language, config(:whisper_language, "en"))
    threads = Keyword.get(opts, :threads, config(:whisper_threads, 4))

    cond do
      is_nil(cli) or not File.exists?(cli) ->
        {:error, {:missing_binary, cli}}

      is_nil(model) or not File.exists?(model) ->
        {:error, {:missing_model, model}}

      not File.exists?(wav_path) ->
        {:error, {:missing_audio, wav_path}}

      true ->
        args = ["-m", model, "-l", lang, "-t", to_string(threads), "-nt", "-f", wav_path]

        case System.cmd(cli, args, stderr_to_stdout: false) do
          {output, 0} -> {:ok, clean_output(output)}
          {output, status} -> {:error, {:exit_status, status, output}}
        end
    end
  end

  defp config(key, default \\ nil), do: Application.get_env(:wiz_home, key, default)

  defp default_path(relpath_key) do
    case config(relpath_key) do
      nil -> nil
      relpath -> Path.join(Application.app_dir(:wiz_home, "priv"), relpath)
    end
  end

  defp clean_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&strip_timestamp/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  # Tolerate builds without -nt honored, or informational bracketed prefixes.
  defp strip_timestamp(line) do
    case String.split(line, "]", parts: 2) do
      [prefix, text] -> if String.contains?(prefix, "-->"), do: String.trim(text), else: line
      _ -> String.trim(line)
    end
  end
end
