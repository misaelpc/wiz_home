---
marp: true
theme: default
paginate: true
header: 'WizHome: Domótica con Elixir'
footer: 'Habla y Elixir Activa las Luces'
style: |
  section {
    font-family: 'Inter', sans-serif;
  }
  h1 {
    color: #3b82f6;
  }
  code {
    background-color: #f3f4f6;
    padding: 2px 6px;
    border-radius: 4px;
  }
---

# Habla y Elixir Activa las Luces
## Domótica con Procesamiento de Audio en Tiempo Real

**Demostrando la versatilidad de Elixir y el poder de Membrane para streams de audio**

---

# Agenda

1. **Visión General del Proyecto**
2. **Arquitectura del Sistema**
3. **Adopción de Elixir: ¿Por qué Elixir?**
4. **Tecnologías Clave**
5. **Características Principales**
6. **Lecciones Aprendidas**

---

# ¿Qué es WizHome?

## Sistema de Domótica Inteligente

### Características Principales:
- 🎤 **Control por Voz**: Comandos de voz en tiempo real
- 💡 **Control Web**: Interfaz LiveView moderna y reactiva
- 🌈 **Control de Color**: RGB + Temperatura de color (Kelvin)
- 📱 **Sin App Móvil**: Todo desde el navegador
- 🏠 **Red Local**: Operación sin internet (excepto transcripción)

### Casos de Uso:
- "Enciende las luces"
- "Apaga todas las luces"
- Control individual y grupal de colores

---

# Arquitectura del Sistema

```
┌─────────────────────────────────────────┐
│           WizHome System                 │
├─────────────────────────────────────────┤
│                                          │
│  ┌──────────┐      ┌──────────┐        │
│  │  Voice   │      │   Web    │        │
│  │ Pipeline │      │ LiveView │        │
│  └────┬─────┘      └────┬─────┘        │
│       │                 │               │
│       ▼                 ▼               │
│  ┌──────────────────────────┐          │
│  │ Voice Controller (GenServer)│        │
│  └──────────┬───────────────┘          │
│             │                           │
│             ▼                           │
│  ┌──────────────────────────┐          │
│  │  Wiz Light API (UDP)     │          │
│  └──────────────────────────┘          │
│                                         │
│  ┌──────────┐      ┌──────────┐       │
│  │ SQLite   │      │  OpenAI  │       │
│  │ (Ecto)   │      │ Whisper  │       │
│  └──────────┘      └──────────┘       │
└─────────────────────────────────────────┘
```

---

# Pipeline de Procesamiento de Voz

## Flujo de Audio en Tiempo Real

```
PortAudio → Audio Chunk Filter → Voice Controller
    ↓              ↓                    ↓
  Micrófono    Segmentación         GenServer
              (3 segundos)        Orquestación
                                      ↓
                            ┌─────────┴─────────┐
                            ↓                   ↓
                        Whisper API      Command Processor
                            ↓                   ↓
                        Transcripción      Parsing (LLM/Regex)
                                              ↓
                                        Wiz Light API
```

### Características:
- **Procesamiento Paralelo**: `Task.async_stream` para múltiples chunks
- **Debouncing**: Previene ejecución rápida de comandos
- **Batching**: Agrupa chunks antes de procesar

---

# Interfaz Web con Phoenix LiveView

## Arquitectura SPA (Single Page Application)

```
Browser (Cliente)
    │
    │ WebSocket (Bidireccional)
    │
Phoenix Server
    │
    ├─ LightsLive (LiveView)
    │  - State Management
    │  - Event Handling
    │  - Real-time Updates
    │
    ├─ Lights Context (Ecto)
    │  - Database Operations
    │
    └─ WizHome API
       - UDP Communication
```

### Ventajas:
- **Sin JavaScript Framework**: Todo en Elixir
- **Estado en el Servidor**: Single Source of Truth
- **Actualizaciones Incrementales**: Solo cambia lo necesario

---

# ¿Por qué Elixir? - Parte 1

## 1. Procesamiento Concurrente Nativo

### Procesamiento Paralelo de Audio
```elixir
chunks_to_process
|> Task.async_stream(
  fn {buffers, stream_format} ->
    transcribe_and_process(buffers, stream_format, state)
  end,
  max_concurrency: 5,
  timeout: 30_000
)
```

**Beneficios:**
- ✅ Procesa múltiples chunks simultáneamente
- ✅ Back-pressure automático
- ✅ Manejo de errores robusto

---

# ¿Por qué Elixir? - Parte 2

## 2. OTP y GenServer para Estado

### Voice Controller como GenServer
```elixir
defmodule WizHome.Voice.VoiceController do
  use GenServer
  
  def init(opts) do
    state = %{
      api_key: api_key,
      light_ips: light_ips,
      pending_chunks: [],
      last_command_time: 0,
      debounce_ms: 1000
    }
    {:ok, state}
  end
end
```

**Ventajas:**
- ✅ Estado consistente y aislado
- ✅ Supervisión automática
- ✅ Tolerancia a fallos

---

# ¿Por qué Elixir? - Parte 3

## 3. Phoenix LiveView para UI Reactiva

### Sin JavaScript Framework
```elixir
defmodule WizHomeWeb.LightsLive do
  use Phoenix.LiveView
  
  def handle_event("set_color", _params, socket) do
    # Lógica en Elixir
    # Actualización automática del DOM
    {:noreply, socket}
  end
end
```

**Beneficios:**
- ✅ Menos código (sin JS)
- ✅ Estado en el servidor
- ✅ Actualizaciones incrementales
- ✅ Type-safe con Elixir

---

# ¿Por qué Elixir? - Parte 4

## 4. Membrane para Streams de Audio

### Pipeline Declarativo
```elixir
defmodule WizHome.Voice.VoicePipeline do
  use Membrane.Pipeline
  
  spec =
    child(:mic, %Membrane.PortAudio.Source{...})
    |> child(:chunk_filter, %AudioChunkFilter{...})
end
```

**Ventajas:**
- ✅ Pipeline funcional y composable
- ✅ Back-pressure automático
- ✅ Manejo de streams en tiempo real
- ✅ Fácil de extender

---

# Stack Tecnológico Completo

## Backend
- **Elixir 1.14+**: Lenguaje funcional
- **Phoenix 1.7**: Framework web
- **Phoenix LiveView**: UI reactiva
- **Ecto + SQLite3**: Base de datos
- **Membrane**: Procesamiento de audio
- **GenServer**: Estado y concurrencia

## Frontend
- **Tailwind CSS**: Estilos
- **Heroicons**: Iconos
- **JavaScript Hooks**: Interactividad mínima (color wheel)

## Servicios Externos
- **OpenAI Whisper API**: Transcripción de voz
- **OpenAI GPT API**: Parsing de comandos (opcional)

## Protocolo
- **UDP**: Comunicación con luces Wiz

---

# Característica 1: Control por Voz

## Flujo Completo

```
1. Captura de Audio
   ↓
2. Segmentación en Chunks (3 segundos)
   ↓
3. Procesamiento Paralelo
   ↓
4. Transcripción (Whisper API)
   ↓
5. Parsing de Comando (LLM o Regex)
   ↓
6. Ejecución con Debouncing
```

### Ejemplo de Comandos:
- "Enciende las luces"
- "Apaga todas las luces"
- "Enciende la luz de la sala"

### Optimizaciones:
- ✅ Procesamiento paralelo de chunks
- ✅ Debouncing (1 segundo)
- ✅ Batching inteligente
- ✅ Fallback a regex si LLM falla

---

# Característica 2: Interfaz Web Moderna

## Funcionalidades

### 1. Registro de Luces
- Agregar/eliminar luces por IP
- Persistencia en SQLite

### 2. Control Individual
- Toggle on/off por luz
- Control de color por luz
- Visualización de último color

### 3. Control Global
- Toggle todas las luces
- Aplicar color a todas

### 4. Selector de Color Avanzado
- Color wheel (hue)
- RGB sliders
- Brightness control
- Color temperature (Kelvin: 2200K-6500K)
- Presets de colores

---

# Característica 3: Selector de Color Avanzado

## Modal de Color

### Controles:
- 🎨 **Color Wheel**: Selección de hue circular
- 🎚️ **Brightness Slider**: 10-100%
- 🌡️ **Temperature Slider**: 2200K (warm) - 6500K (cool)
- 🎨 **Presets**: Colores predefinidos

### Modos:
- **Single**: Aplica a una luz específica
- **All**: Aplica a todas las luces

### Persistencia:
- Guarda último color en base de datos
- Restaura al abrir modal

---

# Patrón: GenServer para Orquestación

## Voice Controller

### Responsabilidades:
1. **Acumular chunks** de audio
2. **Orquestar procesamiento** paralelo
3. **Implementar debouncing** de comandos
4. **Mantener estado** del sistema

### Estado:
```elixir
%{
  api_key: "...",
  light_ips: ["192.168.1.100", ...],
  pending_chunks: [...],
  batch_size: 2,
  batch_timeout_ms: 2000,
  last_command_time: 0,
  debounce_ms: 1000
}
```

### Ventajas:
- ✅ Estado consistente
- ✅ Supervisión automática
- ✅ Tolerancia a fallos
- ✅ Fácil de testear

---

# Patrón: Procesamiento Paralelo

## Task.async_stream para Chunks

### Implementación:
```elixir
chunks_to_process
|> Task.async_stream(
  fn {buffers, stream_format} ->
    transcribe_and_process(buffers, stream_format, state)
  end,
  max_concurrency: 5,
  timeout: 30_000,
  on_timeout: :kill_task
)
```

### Beneficios:
- ✅ **Concurrencia Controlada**: max_concurrency limita recursos
- ✅ **Back-pressure**: Automático
- ✅ **Timeout Handling**: Previene bloqueos
- ✅ **Error Isolation**: Un chunk fallido no afecta otros

---

# Patrón: Phoenix LiveView para SPA

## Single Page Application sin JavaScript

### Arquitectura:
```elixir
defmodule WizHomeWeb.LightsLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    # Estado inicial
    {:ok, socket}
  end
  
  def handle_event("set_color", _params, socket) do
    # Lógica de negocio
    # Actualización automática del DOM
    {:noreply, socket}
  end
end
```

### Ventajas:
- ✅ **Sin JavaScript Framework**: Menos complejidad
- ✅ **Estado en Servidor**: Single source of truth
- ✅ **Actualizaciones Incrementales**: Solo cambia lo necesario
- ✅ **Type Safety**: Errores en compile-time

---

# Membrane: Procesamiento de Streams

## ¿Qué es Membrane?

**Framework de Elixir para procesamiento de multimedia en tiempo real**

### Pipeline de Audio:
```elixir
spec =
  child(:mic, %Membrane.PortAudio.Source{
    device_id: :default,
    sample_format: :s16le
  })
  |> child(:chunk_filter, %AudioChunkFilter{
    controller_pid: controller_pid,
    chunk_duration_ms: 3000
  })
```

### Características:
- ✅ **Back-pressure**: Automático
- ✅ **Composable**: Fácil de extender
- ✅ **Funcional**: Pipeline declarativo
- ✅ **Tiempo Real**: Baja latencia

---

# Persistencia con Ecto

## Schema y Migrations

### Bulb Schema:
```elixir
defmodule WizHome.Lights.Bulb do
  use Ecto.Schema
  
  schema "bulbs" do
    field :ip, :string
    field :name, :string
    field :last_color_r, :integer
    field :last_color_g, :integer
    field :last_color_b, :integer
    field :last_brightness, :integer
    field :last_temperature, :integer
    timestamps()
  end
end
```

### Ventajas de Ecto:
- ✅ **Changesets**: Validación y transformación
- ✅ **Migrations**: Versionado de schema
- ✅ **Queries**: Type-safe queries
- ✅ **SQLite3**: Base de datos ligera

---

# Protocolo Wiz Light (UDP)

## Comunicación con Luces

### Implementación:
```elixir
def set_rgb(ip, {r, g, b}, dimming \\ 75) do
  cmd = %{
    id: 1,
    method: "setPilot",
    params: %{
      r: r, g: g, b: b,
      dimming: dimming
    }
  }
  send_cmd(ip, cmd)
end
```

### Características:
- ✅ **UDP**: Comunicación sin conexión
- ✅ **JSON**: Formato de mensajes
- ✅ **Local Network**: Sin internet requerida
- ✅ **Baja Latencia**: Respuesta inmediata

---

# Lecciones Aprendidas - Parte 1

## 1. Elixir es Excelente para Tiempo Real

### Procesamiento de Audio:
- GenServer maneja estado de forma natural
- Task.async_stream para paralelismo
- Membrane para streams

### Resultado:
- Sistema robusto y concurrente
- Baja latencia
- Fácil de mantener

---

# Lecciones Aprendidas - Parte 2

## 2. LiveView Simplifica el Frontend

### Comparación:
**Tradicional:**
- React/Vue + API REST
- Estado en cliente y servidor
- Sincronización compleja

**LiveView:**
- Todo en Elixir
- Estado solo en servidor
- Actualizaciones automáticas

### Resultado:
- Menos código
- Menos bugs
- Desarrollo más rápido

---

# Lecciones Aprendidas - Parte 3

## 3. Membrane es Poderoso para Multimedia

### Ventajas:
- Pipeline declarativo
- Back-pressure automático
- Fácil de extender

### Uso en WizHome:
- Captura de audio
- Segmentación en chunks
- Integración con GenServer

### Resultado:
- Sistema robusto para audio en tiempo real
- Fácil de mantener y extender

---

# Performance del Sistema

## Métricas Clave

### Procesamiento de Audio:
- **Latencia**: ~2-3 segundos (transcripción incluida)
- **Concurrencia**: 5 chunks en paralelo
- **Debouncing**: 1 segundo entre comandos

### Interfaz Web:
- **Actualizaciones**: Incrementales (solo cambia lo necesario)
- **WebSocket**: Conexión persistente
- **Base de Datos**: SQLite (suficiente para uso local)

### Recursos:
- **Memoria**: ~50-100 MB
- **CPU**: Bajo uso (solo cuando procesa audio)

---

# Casos de Uso Reales

## Escenarios

### 1. Control Rápido
- "Enciende las luces" → Respuesta en ~2-3s
- Útil cuando las manos están ocupadas

### 2. Control de Color
- Interfaz web para ajuste fino
- Guarda preferencias por luz

### 3. Control Grupal
- "Apaga todas las luces" → Todas a la vez
- Útil al salir de casa

### 4. Automatización
- Base para integraciones futuras
- API lista para scripts

---

# Posibles Extensiones

## Ideas para el Futuro

### 1. Más Comandos de Voz
- "Cambia el color a azul"
- "Aumenta el brillo"
- "Luz cálida para leer"

### 2. Programación
- Encender/apagar a horas específicas
- Rutinas diarias

### 3. Integraciones
- Home Assistant
- Google Home / Alexa
- MQTT

### 4. Machine Learning Local
- Whisper local (sin API)
- Modelo de comandos entrenado

---

# Conclusión

## Elixir: Un Lenguaje Versátil

### Demostrado en este Proyecto:
- ✅ **Procesamiento de Audio en Tiempo Real**
- ✅ **Interfaz Web Reactiva**
- ✅ **Concurrencia Nativa**
- ✅ **Tolerancia a Fallos**

### Ventajas Clave:
- **Productividad**: Menos código, más funcionalidad
- **Confiabilidad**: OTP y supervisión
- **Performance**: Concurrencia eficiente
- **Mantenibilidad**: Código claro y funcional

### Para Domótica:
- Elixir es una excelente elección
- Phoenix LiveView simplifica el frontend
- Membrane maneja multimedia con elegancia

---

# Preguntas y Respuestas

## ¿Preguntas?

### Recursos:
- **Elixir**: https://elixir-lang.org
- **Phoenix**: https://www.phoenixframework.org
- **Membrane**: https://membrane.stream

**¡Elixir hace que la domótica sea divertida!**



