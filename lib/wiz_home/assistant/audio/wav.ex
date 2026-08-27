defmodule WizHome.Assistant.Audio.Wav do
  @moduledoc """
  Writes raw s16le mono PCM to a WAV container.

  whisper.cpp reads WAV files (not headerless PCM), so captured audio must be
  wrapped before it's handed to `whisper-cli`.
  """

  def write!(path, pcm_binary, sample_rate \\ 16_000) when is_binary(pcm_binary) do
    data_size = byte_size(pcm_binary)
    byte_rate = sample_rate * 2

    header = <<
      "RIFF",
      36 + data_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      1::little-16,
      sample_rate::little-32,
      byte_rate::little-32,
      2::little-16,
      16::little-16,
      "data",
      data_size::little-32
    >>

    File.write!(path, [header, pcm_binary])
    path
  end
end
