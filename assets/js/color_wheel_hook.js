/* eslint-env browser */

// Circular hue picker. Preview stays local during drag so LiveView is not
// flooded; RGB is sent only when the user presses Done.

export const ColorPicker = {
  mounted() {
    this.hue = parseFloat(this.el.dataset.hue) || 0
    this.saturation = parseFloat(this.el.dataset.saturation)
    this.lightness = parseFloat(this.el.dataset.brightness)
    if (Number.isNaN(this.saturation)) this.saturation = 100
    if (Number.isNaN(this.lightness)) this.lightness = 50

    this.isDragging = false
    this.picker = this.el
    this.hueCanvas = this.el.querySelector("[data-hue-canvas]")
    this.hexInput = this.el.querySelector("#color-picker-hex-input")
    this.swatch = this.el.querySelector("[data-color-swatch]")
    this.doneBtn = this.el.querySelector("#floating-color-picker-done")
    this.hueCtx = this.hueCanvas.getContext("2d")
    this.hueRadius = this.hueCanvas.width / 2

    this.onPointerDown = (event) => this.handlePointerDown(event)
    this.onPointerMove = (event) => this.handlePointerMove(event)
    this.onPointerUp = (event) => this.handlePointerUp(event)
    this.onHexInput = (event) => this.handleHexInput(event)
    this.onDone = (event) => this.handleDone(event)

    this.hueCanvas.style.touchAction = "none"
    this.hueCanvas.addEventListener("pointerdown", this.onPointerDown)
    this.hueCanvas.addEventListener("pointermove", this.onPointerMove)
    this.hueCanvas.addEventListener("pointerup", this.onPointerUp)
    this.hueCanvas.addEventListener("pointercancel", this.onPointerUp)

    if (this.hexInput) {
      this.hexInput.addEventListener("input", this.onHexInput)
      this.hexInput.addEventListener("change", this.onHexInput)
    }

    if (this.doneBtn) {
      this.doneBtn.addEventListener("click", this.onDone)
    }

    this.reposition = () => this.positionPicker()
    this.readyToClose = false
    this.onPointerDownAway = (event) => this.handlePointerDownAway(event)
    window.addEventListener("resize", this.reposition)
    window.addEventListener("scroll", this.reposition, true)
    this.el.style.visibility = "hidden"
    this.positionPicker()
    this.el.style.visibility = "visible"
    window.setTimeout(() => {
      this.readyToClose = true
      document.addEventListener("pointerdown", this.onPointerDownAway)
    }, 150)

    this.drawWheel()
    this.syncPreview()
  },

  updated() {
    this.positionPicker()
  },

  destroyed() {
    if (this.hueCanvas) {
      this.hueCanvas.removeEventListener("pointerdown", this.onPointerDown)
      this.hueCanvas.removeEventListener("pointermove", this.onPointerMove)
      this.hueCanvas.removeEventListener("pointerup", this.onPointerUp)
      this.hueCanvas.removeEventListener("pointercancel", this.onPointerUp)
    }

    if (this.hexInput) {
      this.hexInput.removeEventListener("input", this.onHexInput)
      this.hexInput.removeEventListener("change", this.onHexInput)
    }

    if (this.doneBtn) {
      this.doneBtn.removeEventListener("click", this.onDone)
    }

    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
    document.removeEventListener("pointerdown", this.onPointerDownAway)
  },

  handlePointerDown(event) {
    if (this.distanceFromCenter(event) < this.innerPreviewRadius()) return

    event.preventDefault()
    this.isDragging = true
    if (this.hueCanvas.setPointerCapture) {
      try {
        this.hueCanvas.setPointerCapture(event.pointerId)
      } catch {
        // Some browsers throw if capture is already set.
      }
    }
    this.updateHueFromEvent(event)
  },

  handlePointerMove(event) {
    if (!this.isDragging) return
    event.preventDefault()
    this.updateHueFromEvent(event)
  },

  handlePointerUp(event) {
    if (!this.isDragging) return
    event.preventDefault()
    this.isDragging = false
    this.updateHueFromEvent(event)
  },

  handleHexInput(event) {
    const parsed = this.parseHex(event.target.value)
    if (!parsed) return

    this.setFromRgb(parsed)
    this.drawWheel()
    this.syncPreview({skipHex: true})
  },

  handleDone(event) {
    event.preventDefault()
    event.stopPropagation()
    const rgb = this.currentRgb()
    this.pushEvent("set_color", {r: rgb.r, g: rgb.g, b: rgb.b})
  },

  handlePointerDownAway(event) {
    if (!this.readyToClose) return
    if (this.el.contains(event.target)) return
    this.pushEvent("close_color_modal", {})
  },

  positionPicker() {
    const panel = this.el
    const arrow = panel.querySelector("[data-picker-arrow]")
    const anchorId = panel.dataset.anchorId
    const anchor = anchorId ? document.getElementById(anchorId) : null
    const margin = 16
    const gap = 14

    panel.style.left = "0px"
    panel.style.top = "0px"
    const panelRect = panel.getBoundingClientRect()

    if (!anchor) {
      const centerLeft = Math.max(margin, (window.innerWidth - panelRect.width) / 2)
      const centerTop = Math.max(margin, (window.innerHeight - panelRect.height) / 2)
      panel.style.left = `${centerLeft}px`
      panel.style.top = `${centerTop}px`
      if (arrow) arrow.style.display = "none"
      return
    }

    const anchorRect = anchor.getBoundingClientRect()
    let placement = "top"
    let top = anchorRect.top - panelRect.height - gap

    if (top < margin) {
      placement = "bottom"
      top = anchorRect.bottom + gap
    }

    if (top + panelRect.height > window.innerHeight - margin) {
      top = Math.max(margin, window.innerHeight - panelRect.height - margin)
    }

    let left = anchorRect.left + anchorRect.width / 2 - panelRect.width / 2
    left = Math.max(margin, Math.min(left, window.innerWidth - panelRect.width - margin))

    panel.style.left = `${left}px`
    panel.style.top = `${top}px`

    if (!arrow) return

    arrow.style.display = "block"
    const center = anchorRect.left + anchorRect.width / 2
    const arrowLeft = Math.max(18, Math.min(center - left - 8, panelRect.width - 26))
    arrow.style.left = `${arrowLeft}px`
    arrow.style.top = placement === "top" ? `${panelRect.height - 8}px` : "-8px"
  },

  pointerOffset(event) {
    const rect = this.hueCanvas.getBoundingClientRect()
    const scaleX = this.hueCanvas.width / rect.width
    const scaleY = this.hueCanvas.height / rect.height
    return {
      x: (event.clientX - rect.left) * scaleX - this.hueRadius,
      y: (event.clientY - rect.top) * scaleY - this.hueRadius
    }
  },

  distanceFromCenter(event) {
    const {x, y} = this.pointerOffset(event)
    return Math.sqrt(x * x + y * y)
  },

  innerPreviewRadius() {
    const outer = this.hueRadius - 6
    return outer * 0.62 - 10
  },

  updateHueFromEvent(event) {
    const {x, y} = this.pointerOffset(event)
    const angle = Math.atan2(y, x) * (180 / Math.PI) + 90
    this.hue = ((angle % 360) + 360) % 360
    this.saturation = 100
    this.lightness = 50
    this.drawWheel()
    this.syncPreview()
  },

  drawWheel() {
    const ctx = this.hueCtx
    const center = this.hueRadius
    const outer = this.hueRadius - 6
    const inner = outer * 0.62

    ctx.clearRect(0, 0, this.hueCanvas.width, this.hueCanvas.height)

    ctx.save()
    ctx.translate(center, center)
    ctx.rotate(-Math.PI / 2)
    ctx.translate(-center, -center)

    for (let angle = 0; angle < 360; angle += 0.6) {
      const startAngle = ((angle - 0.6) * Math.PI) / 180
      const endAngle = ((angle + 0.6) * Math.PI) / 180
      const rgb = this.hslToRgb(angle / 360, 1, 0.5)

      ctx.beginPath()
      ctx.arc(center, center, outer, startAngle, endAngle)
      ctx.arc(center, center, inner, endAngle, startAngle, true)
      ctx.closePath()
      ctx.fillStyle = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
      ctx.fill()
    }

    ctx.restore()

    const rgb = this.currentRgb()
    ctx.beginPath()
    ctx.arc(center, center, inner - 10, 0, Math.PI * 2)
    ctx.fillStyle = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
    ctx.fill()
    ctx.lineWidth = 3
    ctx.strokeStyle = "rgba(255, 255, 255, 0.85)"
    ctx.stroke()

    const indicatorRadius = (outer + inner) / 2
    const indicatorAngle = ((this.hue - 90) * Math.PI) / 180
    const ix = center + Math.cos(indicatorAngle) * indicatorRadius
    const iy = center + Math.sin(indicatorAngle) * indicatorRadius

    ctx.beginPath()
    ctx.arc(ix, iy, 9, 0, Math.PI * 2)
    ctx.fillStyle = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
    ctx.fill()
    ctx.lineWidth = 3
    ctx.strokeStyle = "#ffffff"
    ctx.stroke()
  },

  syncPreview(opts = {}) {
    const rgb = this.currentRgb()
    const hex = this.rgbToHex(rgb)

    if (this.hexInput && !opts.skipHex && document.activeElement !== this.hexInput) {
      this.hexInput.value = hex
    }

    if (this.swatch) {
      this.swatch.style.backgroundColor = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
    }

    this.previewAnchor(rgb)
  },

  previewAnchor(rgb) {
    const anchorId = this.picker?.dataset.anchorId
    if (!anchorId || anchorId === "add-mood-button") return

    const anchor = document.getElementById(anchorId)
    if (!anchor) return

    anchor.style.backgroundColor = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`
    anchor.style.opacity = "1"
  },

  currentRgb() {
    return this.hslToRgb(this.hue / 360, this.saturation / 100, this.lightness / 100)
  },

  setFromRgb({r, g, b}) {
    const hsl = this.rgbToHsl(r, g, b)
    this.hue = hsl.hue
    this.saturation = hsl.saturation
    this.lightness = hsl.lightness
  },

  parseHex(value) {
    if (typeof value !== "string") return null
    const hex = value.trim().replace(/^#/, "")
    if (!/^[0-9a-fA-F]{6}$/.test(hex)) return null

    return {
      r: parseInt(hex.slice(0, 2), 16),
      g: parseInt(hex.slice(2, 4), 16),
      b: parseInt(hex.slice(4, 6), 16)
    }
  },

  rgbToHex({r, g, b}) {
    return [r, g, b]
      .map((value) => value.toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase()
  },

  rgbToHsl(r, g, b) {
    const rNorm = r / 255
    const gNorm = g / 255
    const bNorm = b / 255
    const max = Math.max(rNorm, gNorm, bNorm)
    const min = Math.min(rNorm, gNorm, bNorm)
    const delta = max - min
    let hue = 0
    const lightness = (max + min) / 2
    let saturation = 0

    if (delta !== 0) {
      saturation = lightness < 0.5 ? delta / (max + min) : delta / (2 - max - min)
      if (max === rNorm) hue = (gNorm - bNorm) / delta
      else if (max === gNorm) hue = (bNorm - rNorm) / delta + 2
      else hue = (rNorm - gNorm) / delta + 4
      hue = (hue * 60 + 360) % 360
    }

    return {hue, saturation: saturation * 100, lightness: lightness * 100}
  },

  hslToRgb(h, s, l) {
    let r
    let g
    let b

    if (s === 0) {
      r = g = b = l
    } else {
      const hue2rgb = (p, q, t) => {
        let tone = t
        if (tone < 0) tone += 1
        if (tone > 1) tone -= 1
        if (tone < 1 / 6) return p + (q - p) * 6 * tone
        if (tone < 1 / 2) return q
        if (tone < 2 / 3) return p + (q - p) * (2 / 3 - tone) * 6
        return p
      }

      const q = l < 0.5 ? l * (1 + s) : l + s - l * s
      const p = 2 * l - q
      r = hue2rgb(p, q, h + 1 / 3)
      g = hue2rgb(p, q, h)
      b = hue2rgb(p, q, h - 1 / 3)
    }

    return {
      r: Math.round(r * 255),
      g: Math.round(g * 255),
      b: Math.round(b * 255)
    }
  }
}
