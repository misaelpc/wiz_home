export const AnchoredPicker = {
  mounted() {
    this.reposition = this.positionPicker.bind(this)
    window.addEventListener("resize", this.reposition)
    window.addEventListener("scroll", this.reposition, true)
    requestAnimationFrame(this.reposition)
  },

  updated() {
    requestAnimationFrame(this.reposition)
  },

  destroyed() {
    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
  },

  positionPicker() {
    const panel = this.el
    const arrow = panel.querySelector("[data-picker-arrow]")
    const anchorId = panel.dataset.anchorId
    const anchor = anchorId ? document.getElementById(anchorId) : null

    const panelRect = panel.getBoundingClientRect()
    const margin = 12
    const gap = 12

    if (!anchor) {
      const centerLeft = Math.max(margin, (window.innerWidth - panelRect.width) / 2)
      const centerTop = Math.max(margin, (window.innerHeight - panelRect.height) / 2)
      panel.style.left = `${centerLeft}px`
      panel.style.top = `${centerTop}px`
      if (arrow) {
        arrow.style.display = "none"
      }
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
      placement = "top"
      top = Math.max(margin, anchorRect.top - panelRect.height - gap)
    }

    let left = anchorRect.left + anchorRect.width / 2 - panelRect.width / 2
    left = Math.max(margin, Math.min(left, window.innerWidth - panelRect.width - margin))

    panel.style.left = `${left}px`
    panel.style.top = `${top}px`

    if (arrow) {
      arrow.style.display = "block"
      const center = anchorRect.left + anchorRect.width / 2
      const arrowLeft = Math.max(16, Math.min(center - left - 8, panelRect.width - 24))
      arrow.style.left = `${arrowLeft}px`

      if (placement === "top") {
        arrow.style.top = `${panelRect.height - 8}px`
      } else {
        arrow.style.top = "-8px"
      }
    }
  }
}
