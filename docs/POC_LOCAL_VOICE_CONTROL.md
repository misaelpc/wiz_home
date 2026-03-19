# POC: Local Voice Control with Wake Word Detection

## Overview

This document explores replacing the current OpenAI-dependent voice control system with a fully local solution using Elixir's machine learning ecosystem (Nx, Axon, Bumblebee).

### Current State
- Voice transcription: OpenAI Whisper API (cloud)
- Command parsing: GPT-4o-mini API (cloud)
- Latency: ~2-5 seconds per command
- Cost: Per-request API charges
- Privacy: Audio sent to external servers

### Target State
- Wake word detection: Custom Axon model (local)
- Voice transcription: Whisper via Bumblebee/Nx (local)
- Command parsing: Pattern matching or small local LLM (local)
- Latency: <500ms
- Cost: Zero marginal cost
- Privacy: All processing on-device

---

## Architecture Comparison

### Current Architecture
```
Microphone → Membrane → OpenAI Whisper → GPT-4o → Command Execution
                           (Cloud)        (Cloud)
```

### Target Architecture
```
Microphone → Membrane → Wake Word → Local Whisper → Pattern Match → Command
                        (Axon)     (Bumblebee)      (Elixir)
```

---

## Phase 1: Wake Word Detection

### Goal
Detect a custom wake word (e.g., "Hey Wiz", "Oye Casa") to trigger command listening.

### Why Wake Words?
- Reduces continuous transcription overhead
- Clear intent signal from user
- Lower false-positive command execution
- Privacy: Only transcribe after wake word

### Approach Options

#### Option A: Train Custom Model with Axon (Recommended)

**Pros:**
- Pure Elixir inference
- Small model size (~100KB-1MB)
- Fast inference (<50ms)
- Full control over wake word

**Cons:**
- Requires training data collection
- ML expertise needed
- Training typically done in Python first

**Model Architecture:**
```
Input: MFCC Features (40 coefficients × ~100 frames)
       ↓
Conv1D Layer (32 filters, kernel_size=3)
       ↓
BatchNorm + ReLU
       ↓
MaxPool1D
       ↓
Conv1D Layer (64 filters, kernel_size=3)
       ↓
BatchNorm + ReLU
       ↓
GlobalAveragePooling
       ↓
Dense (64 units, ReLU)
       ↓
Dropout (0.3)
       ↓
Dense (2 units, Softmax) → [wake_word, not_wake_word]
```

#### Option B: Use Existing Wake Word Models

**OpenWakeWord (Python, then port):**
- Pre-trained models available
- Can fine-tune for custom words
- Export to ONNX → Load in Nx

**Porcupine/Picovoice:**
- Commercial, but has free tier
- Very accurate
- Can call from Elixir via ports

#### Option C: Keyword Spotting with Whisper

**Approach:**
- Run small Whisper model continuously
- Check transcription for wake word
- Less efficient but simpler

---

## Phase 2: Local Speech-to-Text

### Goal
Run Whisper locally using Bumblebee/Nx.

### Implementation

```elixir
# Load Whisper model at application start
{:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-small"})
{:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-small"})
{:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-small"})
{:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai/whisper-small"})

serving = Bumblebee.Audio.speech_to_text_whisper(
  whisper,
  featurizer,
  tokenizer,
  generation_config,
  defn_options: [compiler: EXLA],
  language: "es"
)

Nx.Serving.start_link(serving, name: WizHome.WhisperServing) vv
```

### Model Size Comparison

| Model | Parameters | Size | RTF* |
|-------|------------|------|------|
| whisper-tiny | 39M | ~150MB | 0.1x |
| whisper-base | 74M | ~290MB | 0.2x |
| whisper-small | 244M | ~970MB | 0.5x |
| whisper-medium | 769M | ~3GB | 1.0x |

*RTF = Real-Time Factor (lower is faster)

**Recommendation:** Start with `whisper-small` for Spanish accuracy.

---

## Phase 3: Local Command Parsing

### Goal
Parse transcribed text into commands without LLM.

### Approach: Enhanced Pattern Matching

```elixir
defmodule WizHome.Voice.LocalCommandParser do
  @moduledoc """
  Local command parser using pattern matching and fuzzy matching.
  """
  
  # Command patterns with synonyms
  @turn_on_words ~w(prende enciende activa)
  @turn_off_words ~w(apaga desactiva)
  @all_words ~w(todas todos todo)
  @light_words ~w(luz luces foco focos lámpara lámparas)
  
  def parse(text) do
    normalized = normalize(text)
    
    cond do
      matches_turn_off_all?(normalized) ->
        {:ok, :turn_off, :all}
      
      matches_turn_on_all?(normalized) ->
        {:ok, :turn_on, :all}
      
      match = matches_turn_off_specific?(normalized) ->
        {:ok, :turn_off, {:index, match}}
      
      match = matches_turn_on_specific?(normalized) ->
        {:ok, :turn_on, {:index, match}}
      
      true ->
        :no_command
    end
  end
  
  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
  end
  
  defp matches_turn_off_all?(words) do
    has_action?(words, @turn_off_words) and
    (has_any?(words, @all_words) or has_any?(words, @light_words))
  end
  
  # ... more pattern matching
end
```

### Optional: Tiny Local LLM

For more flexible command interpretation:

```elixir
# Using a small model like TinyLlama or Phi-2
{:ok, model} = Bumblebee.load_model({:hf, "TinyLlama/TinyLlama-1.1B-Chat-v1.0"})
```

---

## Experiments & Milestones

### Experiment 1: Wake Word Data Collection
**Goal:** Collect training data for custom wake word

**Steps:**
1. Create simple recording script
2. Collect 100+ positive samples ("Hey Wiz")
3. Collect 500+ negative samples (random speech, silence, noise)
4. Augment data (pitch shift, noise, speed)

**Script:**
```elixir
defmodule WizHome.WakeWord.DataCollector do
  @doc """
  Records audio samples for wake word training.
  """
  def record_sample(label, duration_ms \\ 2000) do
    timestamp = System.system_time(:millisecond)
    filename = "data/wake_word/#{label}_#{timestamp}.wav"
    
    # Use existing MicToWav pipeline
    {:ok, pid} = WizHome.start_recording(
      output_file: filename,
      device_id: :default
    )
    
    Process.sleep(duration_ms)
    WizHome.stop_recording(pid)
    
    {:ok, filename}
  end
end
```

### Experiment 2: MFCC Feature Extraction
**Goal:** Extract audio features for model input

**Dependencies:**
```elixir
# mix.exs
{:nx, "~> 0.7"},
{:scholar, "~> 0.3"}  # For signal processing
```

**Implementation:**
```elixir
defmodule WizHome.WakeWord.Features do
  import Nx.Defn
  
  @sample_rate 16_000
  @n_mfcc 40
  @frame_length 400  # 25ms at 16kHz
  @frame_step 160    # 10ms stride
  
  defn compute_mfcc(audio) do
    audio
    |> pre_emphasis()
    |> frame_signal()
    |> apply_window()
    |> compute_fft()
    |> mel_filterbank()
    |> log_compress()
    |> dct()
  end
  
  # ... implementation details
end
```

### Experiment 3: Train Model in Python
**Goal:** Train initial wake word model using PyTorch

**Python Training Script:**
```python
# train_wake_word.py
import torch
import torch.nn as nn
import torchaudio
from torch.utils.data import DataLoader

class WakeWordModel(nn.Module):
    def __init__(self, n_mfcc=40, n_classes=2):
        super().__init__()
        self.conv1 = nn.Conv1d(n_mfcc, 32, kernel_size=3, padding=1)
        self.bn1 = nn.BatchNorm1d(32)
        self.conv2 = nn.Conv1d(32, 64, kernel_size=3, padding=1)
        self.bn2 = nn.BatchNorm1d(64)
        self.pool = nn.AdaptiveAvgPool1d(1)
        self.fc1 = nn.Linear(64, 64)
        self.dropout = nn.Dropout(0.3)
        self.fc2 = nn.Linear(64, n_classes)
    
    def forward(self, x):
        x = torch.relu(self.bn1(self.conv1(x)))
        x = torch.max_pool1d(x, 2)
        x = torch.relu(self.bn2(self.conv2(x)))
        x = self.pool(x).squeeze(-1)
        x = torch.relu(self.fc1(x))
        x = self.dropout(x)
        return self.fc2(x)

# Training loop
model = WakeWordModel()
optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
criterion = nn.CrossEntropyLoss()

for epoch in range(100):
    for batch in train_loader:
        mfcc, labels = batch
        outputs = model(mfcc)
        loss = criterion(outputs, labels)
        
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

# Export to ONNX
torch.onnx.export(model, dummy_input, "wake_word_model.onnx")
```

### Experiment 4: Load ONNX Model in Elixir
**Goal:** Run trained model inference in Elixir

**Dependencies:**
```elixir
{:ortex, "~> 0.1"}  # ONNX Runtime for Elixir
```

**Implementation:**
```elixir
defmodule WizHome.WakeWord.Detector do
  @model_path "priv/models/wake_word_model.onnx"
  
  def start_link(_opts) do
    model = Ortex.load(@model_path)
    GenServer.start_link(__MODULE__, %{model: model}, name: __MODULE__)
  end
  
  def detect(audio_chunk) do
    GenServer.call(__MODULE__, {:detect, audio_chunk})
  end
  
  def handle_call({:detect, audio_chunk}, _from, state) do
    # Extract MFCC features
    mfcc = WizHome.WakeWord.Features.compute_mfcc(audio_chunk)
    
    # Run inference
    {output} = Ortex.run(state.model, {mfcc})
    
    # Get prediction
    probabilities = Nx.softmax(output)
    wake_word_prob = Nx.to_number(probabilities[1])
    
    result = if wake_word_prob > 0.85, do: :detected, else: :not_detected
    {:reply, result, state}
  end
end
```

### Experiment 5: Pure Axon Model (Advanced)
**Goal:** Train and run model entirely in Elixir

```elixir
defmodule WizHome.WakeWord.AxonModel do
  def build_model(input_shape) do
    Axon.input("audio", shape: input_shape)
    |> Axon.conv(32, kernel_size: 3, padding: :same, activation: :relu)
    |> Axon.batch_norm()
    |> Axon.max_pool(kernel_size: 2)
    |> Axon.conv(64, kernel_size: 3, padding: :same, activation: :relu)
    |> Axon.batch_norm()
    |> Axon.global_avg_pool()
    |> Axon.dense(64, activation: :relu)
    |> Axon.dropout(rate: 0.3)
    |> Axon.dense(2, activation: :softmax)
  end
  
  def train(model, train_data, epochs \\ 100) do
    model
    |> Axon.Loop.trainer(:categorical_cross_entropy, :adam)
    |> Axon.Loop.metric(:accuracy)
    |> Axon.Loop.run(train_data, %{}, epochs: epochs)
  end
end
```

### Experiment 6: Bumblebee Whisper Integration
**Goal:** Replace OpenAI Whisper with local Whisper

```elixir
defmodule WizHome.Voice.LocalWhisper do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker
    }
  end
  
  def start_link do
    {:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-small"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-small"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-small"})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai/whisper-small"})
    
    serving = Bumblebee.Audio.speech_to_text_whisper(
      whisper,
      featurizer,
      tokenizer,
      generation_config,
      defn_options: [compiler: EXLA],
      chunk_num_seconds: 30,
      task: :transcribe,
      language: "es"
    )
    
    Nx.Serving.start_link(serving: serving, name: __MODULE__)
  end
  
  def transcribe(audio_binary) do
    Nx.Serving.batched_run(__MODULE__, audio_binary)
  end
end
```

---

## Implementation Roadmap

### Week 1: Setup & Data Collection
- [ ] Add Nx, Axon, Bumblebee, EXLA dependencies
- [ ] Create data collection script
- [ ] Collect 100 positive wake word samples
- [ ] Collect 500 negative samples
- [ ] Implement MFCC feature extraction

### Week 2: Model Training (Python)
- [ ] Setup Python training environment
- [ ] Implement data augmentation
- [ ] Train initial wake word model
- [ ] Evaluate accuracy (target: >95%)
- [ ] Export to ONNX format

### Week 3: Elixir Integration
- [ ] Load ONNX model with Ortex
- [ ] Integrate with Membrane pipeline
- [ ] Create WakeWordDetector GenServer
- [ ] Test end-to-end wake word detection

### Week 4: Local Whisper
- [ ] Setup Bumblebee Whisper serving
- [ ] Replace WhisperClient with LocalWhisper
- [ ] Optimize for latency
- [ ] Test Spanish transcription accuracy

### Week 5: Full Integration
- [ ] Connect wake word → Whisper → Command flow
- [ ] Add local command parser
- [ ] Remove OpenAI dependencies
- [ ] Performance testing & optimization

---

## Dependencies to Add

```elixir
# mix.exs
defp deps do
  [
    # ... existing deps ...
    
    # Machine Learning
    {:nx, "~> 0.7"},
    {:exla, "~> 0.7"},           # GPU/CPU acceleration
    {:axon, "~> 0.6"},           # Neural networks
    {:bumblebee, "~> 0.5"},      # Pre-trained models
    {:ortex, "~> 0.1"},          # ONNX runtime
    
    # Audio Processing
    {:nx_signal, "~> 0.2"},      # Signal processing (FFT, etc.)
  ]
end
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| RAM | 4GB | 8GB+ |
| CPU | 4 cores | 8+ cores |
| GPU | Not required | CUDA-capable (for training) |
| Storage | 2GB | 5GB (for models) |

---

## Metrics to Track

| Metric | Target | Measurement |
|--------|--------|-------------|
| Wake Word Accuracy | >95% | True positives / Total positives |
| False Positive Rate | <1% | False triggers per hour |
| Wake Word Latency | <100ms | Detection time from end of word |
| Transcription WER | <15% | Word Error Rate on Spanish |
| End-to-End Latency | <500ms | Wake word to command execution |
| Memory Usage | <1GB | Runtime memory footprint |

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Low wake word accuracy | High | Collect more diverse training data |
| Slow inference | Medium | Use EXLA compiler, quantization |
| Spanish transcription errors | Medium | Fine-tune Whisper on Spanish commands |
| Memory constraints | Medium | Use smaller models (tiny/base) |
| MFCC implementation bugs | Low | Use proven libraries (nx_signal) |

---

## References

### Elixir ML Ecosystem
- [Nx Documentation](https://hexdocs.pm/nx)
- [Axon Documentation](https://hexdocs.pm/axon)
- [Bumblebee Documentation](https://hexdocs.pm/bumblebee)
- [EXLA Documentation](https://hexdocs.pm/exla)

### Wake Word Detection
- [Honk: PyTorch Keyword Spotting](https://github.com/castorini/honk)
- [OpenWakeWord](https://github.com/dscripka/openWakeWord)
- [Google Speech Commands Dataset](https://www.tensorflow.org/datasets/catalog/speech_commands)

### Audio Features
- [MFCC Explanation](https://haythamfayek.com/2016/04/21/speech-processing-for-machine-learning.html)
- [Librosa (Python reference)](https://librosa.org/)

### Whisper
- [OpenAI Whisper](https://github.com/openai/whisper)
- [Whisper in Bumblebee](https://github.com/elixir-nx/bumblebee/tree/main/examples/whisper)

---

## Appendix A: Sample Data Directory Structure

```
data/
├── wake_word/
│   ├── positive/
│   │   ├── hey_wiz_001.wav
│   │   ├── hey_wiz_002.wav
│   │   └── ...
│   ├── negative/
│   │   ├── random_speech_001.wav
│   │   ├── silence_001.wav
│   │   ├── noise_001.wav
│   │   └── ...
│   └── augmented/
│       ├── hey_wiz_001_pitch_up.wav
│       ├── hey_wiz_001_noise.wav
│       └── ...
└── commands/
    ├── turn_on/
    ├── turn_off/
    └── other/
```

---

## Appendix B: Quick Start Commands

```bash
# Install Elixir ML dependencies
mix deps.get

# Download Whisper model (first run)
iex -S mix
> WizHome.Voice.LocalWhisper.start_link()

# Collect wake word samples
> WizHome.WakeWord.DataCollector.record_sample("positive")
> WizHome.WakeWord.DataCollector.record_sample("negative")

# Train model (Python)
cd python/
python train_wake_word.py --data ../data/wake_word --output ../priv/models/

# Test wake word detection
> WizHome.WakeWord.Detector.start_link([])
> WizHome.WakeWord.Detector.detect(audio_chunk)
```

---

*Document created: January 2026*
*Status: Exploratory / POC Planning*
