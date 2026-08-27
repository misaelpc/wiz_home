# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wiz_home,
  ecto_repos: [WizHome.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :wiz_home, WizHomeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WizHomeWeb.ErrorHTML, json: WizHomeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WizHome.PubSub,
  live_view: [signing_salt: "92tSqHc0"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :wiz_home, WizHome.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  wiz_home: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  wiz_home: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Local Voice Assistant Configuration
config :wiz_home,
  wake_word_threshold: 0.0143,
  wake_word_cooldown_ms: 2_000,
  wake_word_models: ["wakeword.onnx"],
  portaudio_input_device_id: :default,
  # Command capture (mic buffering that follows a wake-word hit)
  capture_silence_peak_threshold: 500,
  capture_silence_duration_ms: 1_200,
  capture_max_duration_ms: 15_000,
  # whisper.cpp — build it under priv/whisper.cpp (see README). Paths are
  # relative to the app's priv dir, resolved at runtime (release-safe).
  whisper_cli_relpath: "whisper.cpp/build/bin/whisper-cli",
  whisper_model_relpath: "whisper.cpp/models/ggml-base.en.bin",
  whisper_language: "en",
  whisper_threads: 4,
  # Ollama — local server must already be running (`ollama serve` / systemd service)
  ollama_base_url: "http://localhost:11434/api",
  ollama_model: "gemma3:1b"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
