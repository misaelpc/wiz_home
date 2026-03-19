# Presentación: WizHome - Domótica con Elixir

## Archivos Disponibles

1. **PRESENTATION.md**: Versión estándar en Markdown (30 slides)
2. **PRESENTATION_MARP.md**: Versión compatible con Marp para renderizado fácil

## Cómo Usar las Presentaciones

### Opción 1: Marp (Recomendado)

Marp es una herramienta que convierte Markdown en presentaciones.

#### Instalación:
```bash
# Con npm
npm install -g @marp-team/marp-cli

# O con Homebrew (macOS)
brew install marp-cli
```

#### Uso:
```bash
# Generar HTML
marp PRESENTATION_MARP.md -o presentation.html

# Generar PDF
marp PRESENTATION_MARP.md -o presentation.pdf

# Generar PowerPoint
marp PRESENTATION_MARP.md -o presentation.pptx

# Modo presentación (servidor local)
marp PRESENTATION_MARP.md --server
```

### Opción 2: VS Code con Extensión Marp

1. Instala la extensión "Marp for VS Code"
2. Abre `PRESENTATION_MARP.md`
3. Presiona `Ctrl+Shift+V` (o `Cmd+Shift+V` en Mac) para vista previa
4. Usa `Ctrl+Shift+P` → "Marp: Export slide deck" para exportar

### Opción 3: Reveal.js

Puedes convertir el Markdown a Reveal.js usando herramientas como:
- [pandoc](https://pandoc.org/)
- [mdx-deck](https://github.com/jxnblk/mdx-deck)

### Opción 4: PowerPoint / Google Slides

1. Copia el contenido de `PRESENTATION.md`
2. Pega en PowerPoint/Google Slides
3. Ajusta el formato según necesites

## Estructura de la Presentación

### Slides Principales:
1. **Título** - Introducción al proyecto
2. **Agenda** - Estructura de la charla
3. **Visión General** - ¿Qué es WizHome?
4. **Arquitectura** - Diagramas del sistema
5. **Elixir Adoption** - ¿Por qué Elixir? (4 slides)
6. **Stack Tecnológico** - Tecnologías usadas
7. **Características** - Funcionalidades principales (3 slides)
8. **Patrones de Diseño** - GenServer, Task.async_stream, LiveView (3 slides)
9. **Membrane** - Procesamiento de audio
10. **Ecto** - Persistencia
11. **UDP Protocol** - Comunicación con luces
12. **Lecciones Aprendidas** - Experiencias (3 slides)
13. **Performance** - Métricas
14. **Casos de Uso** - Escenarios reales
15. **Extensiones Futuras** - Ideas
16. **Conclusión** - Resumen
17. **Preguntas** - Q&A

## Personalización

### Cambiar el Tema (Marp):
Edita el frontmatter en `PRESENTATION_MARP.md`:
```yaml
---
marp: true
theme: default  # Cambia a 'gaia', 'uncover', etc.
paginate: true
---
```

### Agregar Tu Información:
- Edita el slide de "Preguntas" con tu contacto
- Agrega tu GitHub/email
- Personaliza los colores en el `style` del frontmatter

## Tips para la Presentación

1. **Demo en Vivo**: Considera hacer una demostración en vivo
   - Control por voz: "Enciende las luces"
   - Interfaz web: Cambiar colores
   - Control global: Toggle todas las luces

2. **Tiempo Estimado**: ~30-45 minutos
   - 5 min: Introducción y visión general
   - 15 min: Arquitectura y Elixir adoption
   - 10 min: Características y patrones
   - 5 min: Lecciones aprendidas y conclusión
   - 5-10 min: Q&A

3. **Preparación**:
   - Asegúrate de tener el proyecto corriendo
   - Prepara una demo funcional
   - Ten ejemplos de código listos

## Recursos Adicionales

- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Phoenix Framework](https://www.phoenixframework.org)
- [Membrane Framework](https://membrane.stream)
- [Marp Documentation](https://marp.app/)



