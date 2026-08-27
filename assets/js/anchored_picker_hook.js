export const AnchoredPicker = {
  mounted() {
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
  },

  updated() {
    this.positionPicker()
  },

  destroyed() {
    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
    document.removeEventListener("pointerdown", this.onPointerDownAway)
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
  }
}
