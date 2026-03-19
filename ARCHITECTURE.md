# WizHome Architecture Documentation

## Overview

**WizHome** is a smart home automation application built with Elixir and the Phoenix Framework. It provides both a web interface and voice control capabilities to manage Wiz smart light bulbs over a local network using the Wiz Connected protocol.

### Key Features

- **Web-based Dashboard**: Real-time control of smart bulbs via Phoenix LiveView
- **Voice Control**: AI-powered voice commands using OpenAI Whisper and GPT
- **Real-time Audio Processing**: Membrane Framework pipeline for audio capture and processing
- **Persistent Configuration**: SQLite database for storing bulb configurations and color preferences

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| **Web Framework** | Phoenix 1.7.21 |
| **Language** | Elixir 1.14+ |
| **Real-time UI** | Phoenix LiveView 1.0 |
| **Database** | SQLite (via `ecto_sqlite3`) |
| **HTTP Server** | Bandit 1.5 |
| **CSS Framework** | Tailwind CSS 3.4 |
| **Audio Processing** | Membrane Framework |
| **AI/ML APIs** | OpenAI Whisper & GPT-4o-mini |
| **HTTP Client** | Finch |

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              WizHome                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                      Web Layer (WizHomeWeb)                         │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │ │
│  │  │   Router     │──│  LiveView    │──│   Components           │   │ │
│  │  │              │  │ (LightsLive) │  │ (Card, Sidebar, etc.)  │   │ │
│  │  └──────────────┘  └──────────────┘  └────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│                              ▼                                           │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Domain Layer (WizHome)                           │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │ │
│  │  │   Lights     │  │    Voice     │  │    UDP Protocol        │   │ │
│  │  │   Context    │  │   System     │  │   (Wiz Connected)      │   │ │
│  │  └──────────────┘  └──────────────┘  └────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│                              ▼                                           │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Infrastructure Layer                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │ │
│  │  │   Ecto/      │  │   Membrane   │  │   External APIs        │   │ │
│  │  │   SQLite     │  │   Pipeline   │  │   (OpenAI)             │   │ │
│  │  └──────────────┘  └──────────────┘  └────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌──────────────────────────────┐
                    │     Wiz Smart Bulbs          │
                    │   (UDP Port 38899)           │
                    └──────────────────────────────┘
```

---

## Module Structure

### 1. Application Entry Point

#### `WizHome.Application`
The OTP application supervisor that starts all services in the correct order.

**Supervision Tree:**
```
WizHome.Supervisor (one_for_one)
├── WizHomeWeb.Telemetry          # Metrics collection
├── WizHome.Repo                  # Database connection pool
├── Ecto.Migrator                 # Auto-run migrations
├── DNSCluster                    # Distributed Erlang clustering
├── Phoenix.PubSub                # Real-time message broadcasting
├── Finch (WizHome.Finch)         # HTTP connection pool
└── WizHomeWeb.Endpoint           # Phoenix HTTP endpoint
```

---

### 2. Domain Layer

#### `WizHome` (Main Module)
The central API module for controlling Wiz bulbs and voice features.

**UDP Protocol Functions:**
| Function | Description |
|----------|-------------|
| `set_state(ip, boolean)` | Turn bulb on/off |
| `set_rgb(ip, {r,g,b}, dimming)` | Set RGB color (0-255) |
| `set_temp(ip, kelvin, dimming)` | Set color temperature (2200-6500K) |
| `set_scene(ip, scene_id, dimming, speed)` | Set predefined scene |
| `get_status(ip)` | Query current bulb state |

**Audio/Voice Functions:**
| Function | Description |
|----------|-------------|
| `list_audio_devices/0` | List available audio input devices |
| `start_recording/1` | Start audio capture to WAV file |
| `start_voice_control/1` | Start voice command system |
| `stop_voice_control/2` | Stop voice command system |

#### `WizHome.Lights` (Context)
Phoenix context module for bulb persistence.

**CRUD Operations:**
- `list_bulbs/0` - List all registered bulbs
- `get_bulb!/1` - Get bulb by ID
- `get_bulb_by_ip/1` - Get bulb by IP address
- `create_bulb/1` - Register new bulb
- `update_bulb/2` - Update bulb configuration
- `update_bulb_color/2` - Update only color fields
- `delete_bulb/1` - Remove bulb

#### `WizHome.Lights.Bulb` (Schema)
Ecto schema representing a smart bulb.

**Database Schema:**
```elixir
schema "bulbs" do
  field :ip, :string                  # Required, unique
  field :name, :string                # Optional display name
  field :last_color_r, :integer       # 0-255
  field :last_color_g, :integer       # 0-255
  field :last_color_b, :integer       # 0-255
  field :last_brightness, :integer    # 10-100
  field :last_temperature, :integer   # 2200-6500K
  timestamps()
end
```

---

### 3. Voice Control System

The voice control system is a real-time audio processing pipeline that captures microphone input, transcribes speech using OpenAI Whisper, and interprets commands using GPT.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Voice Control Pipeline                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐   ┌─────────────────┐   ┌──────────────────────┐ │
│  │  PortAudio   │──▶│  AudioChunk     │──▶│  VoiceController     │ │
│  │   Source     │   │    Filter       │   │    (GenServer)       │ │
│  │ (Microphone) │   │ (3s chunks)     │   │                      │ │
│  └──────────────┘   └─────────────────┘   └──────────┬───────────┘ │
│                                                       │             │
│                                                       ▼             │
│                           ┌──────────────────────────────────────┐ │
│                           │         WhisperClient                 │ │
│                           │    (Speech-to-Text via OpenAI)        │ │
│                           └──────────────────┬───────────────────┘ │
│                                              │                      │
│                                              ▼                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    CommandProcessor                           │  │
│  │  ┌───────────────────┐    ┌────────────────────────────────┐ │  │
│  │  │ LLMCommandParser  │    │   Regex Fallback               │ │  │
│  │  │  (GPT-4o-mini)    │    │   (Pattern Matching)           │ │  │
│  │  └───────────────────┘    └────────────────────────────────┘ │  │
│  └────────────────────────────────────────┬─────────────────────┘  │
│                                           │                         │
│                                           ▼                         │
│                           ┌──────────────────────────────────────┐ │
│                           │         WizHome.set_state            │ │
│                           │      (UDP to Smart Bulbs)            │ │
│                           └──────────────────────────────────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Voice Modules

| Module | Role |
|--------|------|
| `VoicePipeline` | Membrane pipeline definition for audio capture |
| `AudioChunkFilter` | Accumulates audio buffers into 3-second chunks |
| `VoiceController` | GenServer orchestrating transcription and command execution |
| `WhisperClient` | Converts PCM audio to WAV and calls OpenAI Whisper API |
| `CommandProcessor` | High-level command detection (LLM + regex fallback) |
| `LLMCommandParser` | GPT-based natural language command interpretation |

#### Supported Voice Commands (Spanish)

| Command Pattern | Action |
|----------------|--------|
| "apaga las luces" | Turn off all lights |
| "prende las luces" | Turn on all lights |
| "apaga el foco 1" | Turn off specific bulb |
| "enciende el foco 2" | Turn on specific bulb |

---

### 4. Web Layer

#### `WizHomeWeb.Router`
Defines application routes.

**Routes:**
```elixir
scope "/", WizHomeWeb do
  pipe_through :browser
  
  get "/", PageController, :home
  
  live_session :lights do
    live "/lights", LightsLive, :index           # Register section
    live "/lights/:section", LightsLive, :index  # Admin/Register sections
  end
end
```

#### `WizHomeWeb.LightsLive`
Main LiveView for bulb management with two sections:

**Register Section** (`/lights` or `/lights/register`):
- Add new bulbs by IP address
- View registered bulbs
- Remove bulbs

**Admin Section** (`/lights/admin`):
- Toggle individual lights on/off
- Color picker with hue wheel
- Temperature control (2200K-6500K)
- Brightness control (10-100%)
- Preset colors (Deep Blue, Soft Teal, Cool Green, etc.)
- Apply colors to all lights simultaneously

#### UI Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `Card` | `components/card.ex` | Reusable card wrapper |
| `Sidebar` | `components/sidebar.ex` | Navigation sidebar |
| `Header` | `components/header.ex` | Top navigation bar |
| `MenuItem` | `components/menu_item.ex` | Sidebar menu items |
| `CoreComponents` | `components/core_components.ex` | Form inputs, modals, buttons |

#### JavaScript Hooks

| Hook | File | Purpose |
|------|------|---------|
| `ColorWheel` | `assets/js/color_wheel_hook.js` | Interactive hue wheel picker |

---

### 5. Data Layer

#### Database: SQLite

**Tables:**
| Table | Purpose |
|-------|---------|
| `bulbs` | Stores registered smart bulbs and their last-known color state |

**Migrations:**
1. `20241112000000_create_bulbs.exs` - Initial bulbs table
2. `20251122033645_add_last_temperature_to_bulbs.exs` - Add temperature field

---

## Communication Protocols

### Wiz Connected Protocol (UDP)

WizHome communicates with Wiz smart bulbs using UDP on port **38899**.

**Request Format:**
```json
{
  "id": 1,
  "method": "setPilot",
  "params": {
    "r": 255,
    "g": 128,
    "b": 64,
    "dimming": 75
  }
}
```

**Available Methods:**
| Method | Parameters | Description |
|--------|------------|-------------|
| `setState` | `state: boolean` | Turn bulb on/off |
| `setPilot` | `r, g, b, dimming` | Set RGB color |
| `setPilot` | `temp, dimming` | Set temperature |
| `setPilot` | `sceneId, dimming, speed` | Set scene |
| `getPilot` | `{}` | Get current state |

---

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | For voice control | OpenAI API key for Whisper & GPT |
| `DATABASE_PATH` | Optional | Custom SQLite database path |
| `SECRET_KEY_BASE` | Production | Phoenix secret key |

### Application Config (`config/config.exs`)

```elixir
config :wiz_home,
  ecto_repos: [WizHome.Repo],
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  default_light_ips: [],
  voice_chunk_duration_ms: 3000
```

---

## Data Flow Diagrams

### 1. Web UI Color Change Flow

```
User clicks color       LiveView handles      WizHome context      UDP sent
on color wheel      →   "color_changed"   →   set_rgb/3        →   to bulb
       │                     event                │                   │
       │                       │                  │                   │
       ▼                       ▼                  ▼                   ▼
┌─────────────┐         ┌───────────┐      ┌───────────┐      ┌───────────┐
│ ColorWheel  │    →    │ LightsLive│  →   │  WizHome  │  →   │  Wiz Bulb │
│   (JS Hook) │         │           │      │           │      │  (Device) │
└─────────────┘         └───────────┘      └───────────┘      └───────────┘
                              │
                              ▼
                        ┌───────────┐
                        │  Lights   │
                        │  Context  │
                        │  (Ecto)   │
                        └───────────┘
                              │
                              ▼
                        ┌───────────┐
                        │  SQLite   │
                        │    DB     │
                        └───────────┘
```

### 2. Voice Command Flow

```
Microphone      AudioChunk     VoiceController    WhisperClient    OpenAI
   │                 │              │                   │           Whisper
   │  PCM Audio      │              │                   │              │
   ├────────────────▶│  3s chunk    │                   │              │
   │                 ├─────────────▶│   WAV conversion  │              │
   │                 │              ├──────────────────▶│  HTTP POST   │
   │                 │              │                   ├─────────────▶│
   │                 │              │                   │              │
   │                 │              │                   │◀─────────────┤
   │                 │              │◀──────────────────┤  Transcribed │
   │                 │              │      text         │     text     │
   │                 │              │                   │              │
   │                 │              │                   │              │
   │                 │              ▼                   │              │
   │                 │       CommandProcessor          │              │
   │                 │       (LLM or Regex)            │              │
   │                 │              │                   │              │
   │                 │              ▼                   │              │
   │                 │       WizHome.set_state         │              │
   │                 │       (UDP to bulb)             │              │
```

---

## OTP Patterns Used

| Pattern | Usage |
|---------|-------|
| **Supervision Tree** | `WizHome.Application` supervises all services |
| **GenServer** | `VoiceController` manages voice command state |
| **Membrane Pipeline** | Audio capture and processing |
| **Task.async_stream** | Parallel audio chunk processing |
| **Process Registry** | Named GenServer for `VoiceController` |

---

## Security Considerations

1. **Network Isolation**: Wiz bulbs communicate on local network only (UDP)
2. **API Key Management**: OpenAI keys should be provided via environment variables
3. **CSRF Protection**: Phoenix's built-in CSRF tokens for form submissions
4. **Input Validation**: IP address format validation on bulb registration

---

## Deployment

### Development
```bash
mix setup           # Install dependencies and setup database
mix phx.server      # Start server at localhost:4000
```

### Production
```bash
MIX_ENV=prod mix release
_build/prod/rel/wiz_home/bin/wiz_home start
```

---

## Dependencies Summary

### Core
- `phoenix` - Web framework
- `phoenix_live_view` - Real-time UI
- `ecto_sql` + `ecto_sqlite3` - Database

### Audio Processing
- `membrane_core` - Media processing framework
- `membrane_portaudio_plugin` - Audio capture
- `membrane_wav_plugin` - WAV encoding
- `membrane_file_plugin` - File output

### HTTP & APIs
- `finch` - HTTP client for OpenAI APIs
- `jason` - JSON encoding/decoding

### Frontend
- `tailwind` - CSS framework
- `esbuild` - JavaScript bundler
- `heroicons` - Icon library

---

## Future Considerations

1. **Scene Management**: Add support for custom light scenes
2. **Scheduling**: Time-based automation for lights
3. **Multi-room Support**: Group bulbs by room/location
4. **Real-time Sync**: PubSub for multi-user state synchronization
5. **Mobile App**: Phoenix LiveView native or dedicated mobile client
6. **Local Voice Processing**: Replace OpenAI with on-device Whisper model

---

*Document generated: January 2026*
*Version: 0.1.0*
