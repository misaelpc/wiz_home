defmodule WizHome.Assistant.WakeWord.Detector do
  @moduledoc """
  OpenWakeWord streaming inference engine using Ortex.

  Feeds 16 kHz s16le mono PCM and produces per-model detection scores.
  Requires `melspectrogram.onnx`, `embedding_model.onnx`, and at least one
  wakeword classifier `.onnx` under `priv/models/openwakeword/`.
  """

  @ortex_cpu Nx.BinaryBackend

  @chunk 1280
  @mel_tail 480
  @mel_rows 76
  @mel_bins 32
  @embed_dim 96
  @feature_max_rows 120
  @raw_max 160_000
  @warmup_rows 5
  @mel_buf_max 970

  defmodule Preprocessor do
    @moduledoc false
    defstruct [:raw, :mel_buf, :feature_buf, :acc, :rem, :mel_m, :emb_m]
  end

  defstruct [:mel, :embedding, :wakewords, :pre]

  def default_asset_dir do
    Application.app_dir(:wiz_home, "priv/models/openwakeword")
  end

  def load(opts \\ []) when is_list(opts) do
    dir = default_asset_dir()

    mel_p = Keyword.get(opts, :melspec_path) || Path.join(dir, "melspectrogram.onnx")
    emb_p = Keyword.get(opts, :embedding_path) || Path.join(dir, "embedding_model.onnx")

    wws =
      case Keyword.get(opts, :wakeword_paths) do
        ps when is_list(ps) and ps != [] ->
          ps

        _ ->
          Application.get_env(:wiz_home, :wake_word_models, [])
      end

    wws =
      Enum.map(wws, fn p ->
        if is_binary(p) and Path.type(p) == :relative and not String.starts_with?(p, "/") do
          Path.join(dir, p)
        else
          Path.expand(p)
        end
      end)

    cond do
      not File.exists?(mel_p) -> {:error, {:missing_onnx, mel_p}}
      not File.exists?(emb_p) -> {:error, {:missing_onnx, emb_p}}
      wws == [] -> {:error, :no_wakeword_models}
      not Enum.all?(wws, &File.exists?/1) -> {:error, {:missing_wakeword, wws}}
      true ->
        mel = Ortex.load(mel_p)
        emb = Ortex.load(emb_p)

        {:ok,
         %__MODULE__{
           mel: mel,
           embedding: emb,
           wakewords: Enum.map(wws, &wak_spec/1),
           pre: pre_init(mel, emb)
         }}
    end
  end

  defp wak_spec(path) do
    %{name: path |> Path.basename() |> Path.rootname(), model: Ortex.load(path), n_feat: 16}
  end

  @doc "Feed s16le PCM binary. Returns `{:ok, detector, scores_map}` when an 80ms step ran."
  def feed(%__MODULE__{} = det, xs) when is_list(xs), do: feed(det, s16_list_to_bin(xs))

  def feed(%__MODULE__{} = det, bin) when is_binary(bin) do
    {pre, fired?} = pre_feed(det.pre, bin)
    det = %{det | pre: pre}

    scores =
      if fired? do
        classify_all(det)
      else
        %{}
      end

    {:ok, det, scores}
  end

  def reset(%__MODULE__{mel: m, embedding: e} = det) do
    %{det | pre: pre_init(m, e)}
  end

  # --- Initialization ---

  defp pre_init(mel_m, emb_m) do
    mel0 = Nx.broadcast(1.0, {@mel_rows, @mel_bins}) |> Nx.backend_copy(@ortex_cpu)

    %Preprocessor{
      raw: [],
      mel_buf: mel0,
      feature_buf: bootstrap_rows(mel_m, emb_m),
      acc: 0,
      rem: <<>>,
      mel_m: mel_m,
      emb_m: emb_m
    }
  end

  defp bootstrap_rows(mel_m, emb_m) do
    noise = for(_ <- 1..64_000, do: :rand.uniform(65_534) - 32_767)
    spec = mel_chain(mel_m, noise)
    emb_rows_from_spec(emb_m, spec)
  end

  # --- Mel spectrogram ---

  defp mel_chain(mel_m, int16s) do
    int16s
    |> Enum.chunk_every(@chunk, @chunk, :discard)
    |> Enum.reduce(nil, fn c, acc ->
      blk = mel_one(mel_m, c)
      if acc == nil, do: blk, else: Nx.concatenate([acc, blk], axis: 0)
    end)
    |> case do
      nil -> Nx.broadcast(0.0, {1, @mel_bins})
      t -> t
    end
  end

  defp mel_one(mel_m, chunk) when is_list(chunk) do
    t =
      chunk
      |> Enum.map(&(&1 * 1.0))
      |> Nx.tensor(type: :f32, backend: @ortex_cpu)
      |> Nx.new_axis(0)

    out = Ortex.run(mel_m, {ensure_in(t)})
    spec = elem(out, 0) |> to_bb_f32() |> Nx.squeeze(axes: [0])
    spec = mel_to_time_by_melbins(spec)
    Nx.divide(spec, 10) |> Nx.add(2)
  end

  defp mel_to_time_by_melbins(%Nx.Tensor{} = t) do
    m = @mel_bins

    case Nx.shape(t) do
      {_, ^m} ->
        t

      {a, b, ^m} ->
        Nx.reshape(t, {a * b, m})

      {a, b, c, ^m} ->
        Nx.reshape(t, {a * b * c, m})

      shape ->
        dims = Tuple.to_list(shape)

        if List.last(dims) != m do
          raise ArgumentError,
                "mel ONNX: expected last dim #{@mel_bins}, got shape #{inspect(shape)}"
        end

        n = Enum.reduce(Enum.drop(dims, -1), 1, &*/2)
        Nx.reshape(t, {n, m})
    end
  end

  # --- Embedding ---

  defp emb_rows_from_spec(emb_m, spec) do
    spec = mel_to_time_by_melbins(spec)
    {r, _} = Nx.shape(spec)
    win = @mel_rows
    step = 8

    ws =
      0..max(r - win, 0)
      |> Enum.filter(fn i -> rem(i, step) == 0 and i + win <= r end)
      |> Enum.map(fn i ->
        spec
        |> Nx.slice([i, 0], [win, @mel_bins])
        |> Nx.new_axis(0)
        |> Nx.new_axis(-1)
      end)

    case ws do
      [] ->
        Nx.broadcast(0.0, {1, @embed_dim}) |> Nx.backend_copy(@ortex_cpu)

      _ ->
        batch = ws |> Enum.map(&ensure_in/1) |> batch_cat()
        out = Ortex.run(emb_m, {batch})
        t = elem(out, 0) |> to_bb_f32()
        norm_emb_matrix(t)
    end
    |> trim_feat()
  end

  defp batch_cat(tensors) do
    Enum.reduce(tensors, nil, fn x, a ->
      if a == nil, do: x, else: Nx.concatenate([a, x], axis: 0)
    end)
  end

  defp norm_emb_matrix(t) do
    d = @embed_dim

    case Nx.shape(t) do
      {_, ^d} -> t
      {^d} -> Nx.new_axis(t, 0)
      {1, _, ^d} -> Nx.squeeze(t, axes: [0])
      _ -> Nx.reshape(t, {:auto, d})
    end
  end

  defp emb_one(emb_m, x_1_76_32_1) do
    out = Ortex.run(emb_m, {ensure_in(x_1_76_32_1)})
    t = elem(out, 0) |> to_bb_f32()
    t = Nx.reshape(t, {:auto, @embed_dim})

    case Nx.shape(t) do
      {1, _} -> t
      {n, _} when n > 1 -> Nx.slice(t, [0, 0], [1, @embed_dim])
    end
  end

  # --- PCM feeding ---

  defp pre_feed(%Preprocessor{rem: r0} = p, bin) do
    full = r0 <> bin
    samples = for(<<s::little-signed-16 <- full>>, do: s)
    p = %{p | rem: <<>>}
    feed_int16_samples(p, samples)
  end

  defp feed_int16_samples(p, []), do: {p, false}

  defp feed_int16_samples(%Preprocessor{acc: acc} = p, xs) when is_list(xs) do
    n = length(xs)

    if acc + n >= @chunk do
      total = acc + n
      remc = rem(total, @chunk)

      if remc != 0 do
        {head, tail} = Enum.split(xs, n - remc)
        p = buf(p, head)
        p = %{p | acc: p.acc + length(head), rem: s16_list_to_bin(tail)}
        maybe_frame(p)
      else
        p = buf(p, xs)
        p = %{p | acc: p.acc + n}
        maybe_frame(p)
      end
    else
      p = buf(p, xs)
      p = %{p | acc: p.acc + n}
      maybe_frame(p)
    end
  end

  defp buf(p, xs), do: %{p | raw: trim_raw(p.raw ++ xs)}

  defp trim_raw(raw) do
    if length(raw) > @raw_max, do: Enum.take(raw, -@raw_max), else: raw
  end

  defp maybe_frame(%Preprocessor{acc: a} = p) when a >= @chunk and rem(a, @chunk) == 0 do
    if length(p.raw) < 400 do
      raise ArgumentError, "internal buffer < 400 samples"
    end

    p = mel_stream_append(p, a)
    k = div(a, @chunk)

    p =
      if k >= 1 do
        Enum.reduce((k - 1)..0//-1, p, fn i, q ->
          ndx = -8 * i
          nmel = Nx.axis_size(q.mel_buf, 0)

          s =
            if ndx == 0 do
              nmel - @mel_rows
            else
              nmel - @mel_rows + ndx
            end

          if s >= 0 and s + @mel_rows <= nmel do
            win =
              q.mel_buf
              |> Nx.slice([s, 0], [@mel_rows, @mel_bins])
              |> Nx.as_type(:f32)
              |> Nx.new_axis(0)
              |> Nx.new_axis(-1)

            row = emb_one(q.emb_m, win)
            %{q | feature_buf: vstack(q.feature_buf, row)}
          else
            q
          end
        end)
      else
        p
      end

    p = %{p | acc: 0, feature_buf: trim_feat(p.feature_buf)}
    {p, true}
  end

  defp maybe_frame(p), do: {p, false}

  defp mel_stream_append(%Preprocessor{raw: raw, mel_buf: mb, mel_m: mm} = p, n_samples) do
    take = min(length(raw), n_samples + @mel_tail)
    sl = Enum.take(raw, -take)

    rows =
      if length(sl) <= @chunk do
        mel_one(mm, sl)
      else
        sl
        |> Enum.chunk_every(@chunk, @chunk, :discard)
        |> Enum.map(&mel_one(mm, &1))
        |> Enum.reduce(nil, fn blk, acc ->
          if acc == nil, do: blk, else: Nx.concatenate([acc, blk], axis: 0)
        end)
      end

    mb2 = Nx.concatenate([mb, rows], axis: 0)
    r = Nx.axis_size(mb2, 0)

    mb3 =
      if r > @mel_buf_max,
        do: Nx.slice(mb2, [r - @mel_buf_max, 0], [@mel_buf_max, @mel_bins]),
        else: mb2

    %{p | mel_buf: mb3}
  end

  # --- Classification ---

  defp classify_all(%__MODULE__{wakewords: wws, pre: pre}) do
    rows = Nx.axis_size(pre.feature_buf, 0)

    for w <- wws, into: %{} do
      inp = slice_feat(pre, w.n_feat)
      score = if rows < @warmup_rows, do: 0.0, else: wak_run(w.model, inp)
      {w.name, score}
    end
  end

  defp wak_run(model, inp) do
    out = Ortex.run(model, {ensure_in(inp)})
    elem(out, 0) |> to_bb_f32() |> Nx.squeeze() |> Nx.to_number()
  end

  defp slice_feat(%Preprocessor{feature_buf: f}, n) when n > 0 do
    {r, _} = Nx.shape(f)
    k = min(n, r)
    f |> Nx.slice([r - k, 0], [k, @embed_dim]) |> Nx.new_axis(0) |> Nx.as_type(:f32)
  end

  # --- Helpers ---

  defp vstack(f, row), do: Nx.concatenate([f, row], axis: 0)

  defp trim_feat(f) do
    {r, _} = Nx.shape(f)

    if r > @feature_max_rows,
      do: Nx.slice(f, [r - @feature_max_rows, 0], [@feature_max_rows, @embed_dim]),
      else: f
  end

  defp ensure_in(%Nx.Tensor{} = t) do
    case t.data do
      %Ortex.Backend{} -> Nx.backend_transfer(t, @ortex_cpu)
      %Nx.BinaryBackend{} -> t
      _ -> Nx.backend_copy(t, @ortex_cpu)
    end
  end

  defp to_bb_f32(t), do: t |> Nx.backend_transfer(@ortex_cpu) |> Nx.as_type(:f32)

  defp s16_list_to_bin(xs), do: for(s <- xs, into: <<>>, do: <<s::little-signed-16>>)
end
