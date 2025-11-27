// Color Wheel Hook for Phoenix LiveView
// Implements a circular hue selector and saturation/brightness square

export const ColorWheel = {
  mounted() {
    console.log("ColorWheel: Mounted with data attributes", {
      hue: this.el.dataset.hue,
      saturation: this.el.dataset.saturation,
      brightness: this.el.dataset.brightness
    });
    
    // Read initial values from data attributes (these come from the current color)
    this.hue = this.el.dataset.hue ? parseFloat(this.el.dataset.hue) : 0;
    this.saturation = this.el.dataset.saturation ? parseFloat(this.el.dataset.saturation) : 100;
    this.lightness = this.el.dataset.brightness ? parseFloat(this.el.dataset.brightness) : 50; // brightness in dataset is actually HSL lightness
    
    console.log("ColorWheel: Initial HSL values from data", {
      hue: this.hue,
      saturation: this.saturation,
      lightness: this.lightness
    });
    
    this.hueCanvas = this.el.querySelector('[data-hue-canvas]');
    this.hueCtx = this.hueCanvas.getContext('2d');
    
    this.hueRadius = this.hueCanvas.width / 2;
    
    // When user interacts, we'll set saturation to 100% and lightness to 50%
    // But for initial display, keep the original values so the preview matches
    
    console.log("ColorWheel: Canvas dimensions", {
      hueRadius: this.hueRadius
    });
    
    this.isDraggingHue = false;
    
    this.drawHueWheel();
    this.updateIndicators();
    
    this.setupEventListeners();
  },
  
  updated() {
    // Update when LiveView sends new color values
    const newHue = this.el.dataset.hue ? parseFloat(this.el.dataset.hue) : this.hue;
    const newSaturation = this.el.dataset.saturation ? parseFloat(this.el.dataset.saturation) : this.saturation;
    const newLightness = this.el.dataset.brightness ? parseFloat(this.el.dataset.brightness) : this.lightness; // brightness in dataset is actually HSL lightness
    
    console.log("ColorWheel: Updated called", {
      old: { hue: this.hue, saturation: this.saturation, lightness: this.lightness },
      new: { hue: newHue, saturation: newSaturation, lightness: newLightness },
      changed: newHue !== this.hue || newSaturation !== this.saturation || newLightness !== this.lightness
    });
    
    if (newHue !== this.hue || newSaturation !== this.saturation || newLightness !== this.lightness) {
      this.hue = newHue;
      this.saturation = newSaturation;
      this.lightness = newLightness;
      this.updateIndicators();
    }
  },
  
  setupEventListeners() {
    // Hue wheel events
    this.hueCanvas.addEventListener('mousedown', (e) => this.startHueDrag(e));
    this.hueCanvas.addEventListener('mousemove', (e) => this.dragHue(e));
    this.hueCanvas.addEventListener('mouseup', () => this.stopHueDrag());
    this.hueCanvas.addEventListener('mouseleave', () => this.stopHueDrag());
    
    // Touch events for hue
    this.hueCanvas.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.startHueDrag(e.touches[0]);
    });
    this.hueCanvas.addEventListener('touchmove', (e) => {
      e.preventDefault();
      this.dragHue(e.touches[0]);
    });
    this.hueCanvas.addEventListener('touchend', () => this.stopHueDrag());
  },
  
  drawHueWheel() {
    const centerX = this.hueRadius;
    const centerY = this.hueRadius;
    const radius = this.hueRadius - 10;
    
    // Rotate the entire drawing by -90° so that hue 0° (red) is at the top
    this.hueCtx.save();
    this.hueCtx.translate(centerX, centerY);
    this.hueCtx.rotate(-Math.PI / 2); // Rotate -90 degrees
    this.hueCtx.translate(-centerX, -centerY);
    
    for (let angle = 0; angle < 360; angle += 0.5) {
      const startAngle = (angle - 0.5) * Math.PI / 180;
      const endAngle = (angle + 0.5) * Math.PI / 180;
      
      this.hueCtx.beginPath();
      this.hueCtx.moveTo(centerX, centerY);
      this.hueCtx.arc(centerX, centerY, radius, startAngle, endAngle);
      this.hueCtx.closePath();
      
      const hue = angle;
      const rgb = this.hslToRgb(hue / 360, 1, 0.5);
      this.hueCtx.fillStyle = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`;
      this.hueCtx.fill();
    }
    
    this.hueCtx.restore();
    
    // Draw inner circle (transparent center)
    this.hueCtx.beginPath();
    this.hueCtx.arc(centerX, centerY, radius * 0.6, 0, 2 * Math.PI);
    this.hueCtx.fillStyle = '#ffffff';
    this.hueCtx.fill();
  },
  
  drawSaturationBrightness() {
    // Clear canvas
    this.sbCtx.fillStyle = '#ffffff';
    this.sbCtx.fillRect(0, 0, this.sbSize, this.sbSize);
    
    // Draw gradient
    const baseColor = this.hslToRgb(this.hue / 360, 1, 0.5);
    
    // Horizontal gradient (saturation: left = gray, right = full color)
    for (let x = 0; x < this.sbSize; x++) {
      const saturation = x / this.sbSize;
      const leftColor = this.hslToRgb(this.hue / 360, 0, 0.5);
      const rightColor = baseColor;
      
      const gradient = this.sbCtx.createLinearGradient(x, 0, x, this.sbSize);
      // Top (brightness = 1) to bottom (brightness = 0)
      const topR = Math.round(leftColor.r + (rightColor.r - leftColor.r) * saturation);
      const topG = Math.round(leftColor.g + (rightColor.g - leftColor.g) * saturation);
      const topB = Math.round(leftColor.b + (rightColor.b - leftColor.b) * saturation);
      
      const bottomR = Math.round(topR * 0);
      const bottomG = Math.round(topG * 0);
      const bottomB = Math.round(topB * 0);
      
      gradient.addColorStop(0, `rgb(${topR}, ${topG}, ${topB})`);
      gradient.addColorStop(1, `rgb(${bottomR}, ${bottomG}, ${bottomB})`);
      
      this.sbCtx.fillStyle = gradient;
      this.sbCtx.fillRect(x, 0, 1, this.sbSize);
    }
  },
  
  updateIndicators() {
    // Draw hue indicator (on the hue wheel)
    this.drawHueIndicator();
  },
  
  drawHueIndicator() {
    // Redraw hue wheel to clear old indicator
    this.drawHueWheel();
    
    const centerX = this.hueRadius;
    const centerY = this.hueRadius;
    const radius = this.hueRadius - 10;
    const indicatorRadius = (radius + radius * 0.6) / 2; // Middle of the ring
    // Convert hue to radians: hue 0 = red (right), but we want it at top, so subtract 90
    // Also, atan2 uses y, x but we want 0° at top, so we need to adjust
    const angle = (this.hue - 90) * Math.PI / 180;
    
    const x = centerX + Math.cos(angle) * indicatorRadius;
    const y = centerY + Math.sin(angle) * indicatorRadius;
    
    console.log("ColorWheel: Drawing indicator at", { hue: this.hue, angle: angle * 180 / Math.PI, x, y, indicatorRadius });
    
    // Draw indicator circle
    this.hueCtx.beginPath();
    this.hueCtx.arc(x, y, 8, 0, 2 * Math.PI);
    this.hueCtx.strokeStyle = '#ffffff';
    this.hueCtx.lineWidth = 3;
    this.hueCtx.stroke();
    this.hueCtx.fillStyle = '#000000';
    this.hueCtx.fill();
  },
  
  startHueDrag(e) {
    this.isDraggingHue = true;
    this.updateHueFromEvent(e);
  },
  
  dragHue(e) {
    if (this.isDraggingHue) {
      this.updateHueFromEvent(e);
    }
  },
  
  stopHueDrag() {
    this.isDraggingHue = false;
  },
  
  updateHueFromEvent(e) {
    const rect = this.hueCanvas.getBoundingClientRect();
    const x = e.clientX - rect.left - this.hueRadius;
    const y = e.clientY - rect.top - this.hueRadius;
    
    // Calculate distance from center to check if click is within the wheel ring
    const distance = Math.sqrt(x * x + y * y);
    const innerRadius = this.hueRadius * 0.6;
    const outerRadius = this.hueRadius - 10;
    
    // Only update if click is within the wheel ring (between inner and outer radius)
    if (distance < innerRadius || distance > outerRadius) {
      return;
    }
    
    // Calculate angle: atan2 gives angle from positive x-axis
    // We want 0° at top (12 o'clock), so we adjust
    // atan2(y, x): (0, -1) = -90°, (1, 0) = 0°, (0, 1) = 90°, (-1, 0) = 180°
    // We want: (0, -1) = 0°, (1, 0) = 90°, (0, 1) = 180°, (-1, 0) = 270°
    // So: angle = atan2(y, x) * 180 / PI + 90, then normalize
    let angle = Math.atan2(y, x) * 180 / Math.PI + 90;
    this.hue = ((angle % 360) + 360) % 360;
    
    // Keep saturation at 100% and lightness at 50% for full vibrant colors when user interacts
    this.saturation = 100;
    this.lightness = 50;
    
    console.log("ColorWheel: Hue updated to", this.hue, "from angle", angle, "with saturation", this.saturation, "lightness", this.lightness);
    
    this.updateIndicators();
    this.sendColorToLiveView();
  },
  
  sendColorToLiveView() {
    console.log("ColorWheel: Current HSL values", {
      hue: this.hue,
      saturation: this.saturation,
      lightness: this.lightness
    });
    
    const rgb = this.hslToRgb(this.hue / 360, this.saturation / 100, this.lightness / 100);
    
    console.log("ColorWheel: Sending color to LiveView", rgb);
    console.log("ColorWheel: pushEvent available?", typeof this.pushEvent);
    
    // pushEvent should be available on the hook context in Phoenix LiveView
    if (this.pushEvent) {
      try {
        this.pushEvent("color_changed", {
          r: rgb.r,
          g: rgb.g,
          b: rgb.b
        });
        console.log("ColorWheel: Event sent via pushEvent");
      } catch (e) {
        console.error("ColorWheel: Error sending event", e);
      }
    } else {
      console.warn("ColorWheel: pushEvent not available, trying alternative method");
      // Try to find the LiveView and push event directly
      const liveViewEl = this.el.closest('[data-phx-main]') || document.querySelector('[data-phx-main]');
      if (liveViewEl && liveViewEl.__view) {
        liveViewEl.__view.pushEvent("color_changed", {
          r: rgb.r,
          g: rgb.g,
          b: rgb.b
        });
        console.log("ColorWheel: Event sent via LiveView element");
      } else {
        console.error("ColorWheel: Could not find LiveView element to send event");
      }
    }
  },
  
  hslToRgb(h, s, l) {
    let r, g, b;
    
    if (s === 0) {
      r = g = b = l; // achromatic
    } else {
      const hue2rgb = (p, q, t) => {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1/6) return p + (q - p) * 6 * t;
        if (t < 1/2) return q;
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
        return p;
      };
      
      const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      const p = 2 * l - q;
      r = hue2rgb(p, q, h + 1/3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1/3);
    }
    
    return {
      r: Math.round(r * 255),
      g: Math.round(g * 255),
      b: Math.round(b * 255)
    };
  }
};

