import { Controller } from "@hotwired/stimulus"

// The landing page hero: storyboard frames climbing a 3D helix, like film through a projector.
// Each frame is a painted "archive shot" labelled the way the storyboard labels scenes (✓ CHECKED,
// FILLER, AI). Every person in them is a silhouette seen from behind, as the AI image rules require.
// three.js is imported here rather than preloaded, so the app's own pages never download it.
const FRAMES = 22
const RADIUS = 3.4
const TURN = Math.PI * 2 / 7.5
const RISE = 0.5
const BADGES = [ [ "✓ CHECKED", "#7cc7b5" ], [ "✓ CHECKED", "#7cc7b5" ], [ "FILLER", "#a29d98" ], [ "✓ CHECKED", "#7cc7b5" ], [ "AI", "#f0a43a" ] ]

export default class extends Controller {
  static targets = ["canvas", "timecode"]

  async connect() {
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.random = seededRandom(7)
    this.startedAt = performance.now()

    let THREE
    try {
      THREE = await import("three")
      this.renderer = new THREE.WebGLRenderer({ canvas: this.canvasTarget, antialias: true, alpha: true })
    } catch {
      return // No WebGL: the hero keeps its plain glow.
    }
    if (!this.element.isConnected) return this.renderer.dispose()

    this.THREE = THREE
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
    this.scene = new THREE.Scene()
    this.scene.fog = new THREE.Fog(0x0f1016, 7.5, 15)
    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 50)
    this.camera.position.set(0, 0, 10)
    this.pointer = { x: 0, y: 0, smoothX: 0, smoothY: 0 }
    this.scrollBoost = 0
    this.lastScroll = window.scrollY
    this.rotation = 0

    await document.fonts?.load('500 13px "JetBrains Mono"').catch(() => {})
    if (!this.element.isConnected) return this.disconnect()
    this.buildHelix()
    this.buildDust()

    this.onResize = () => this.resize()
    this.onPointer = (e) => { this.pointer.x = e.clientX / innerWidth - 0.5; this.pointer.y = e.clientY / innerHeight - 0.5 }
    this.onScroll = () => { this.scrollBoost += (window.scrollY - this.lastScroll) * 0.0006; this.lastScroll = window.scrollY }
    window.addEventListener("resize", this.onResize)
    window.addEventListener("pointermove", this.onPointer)
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.visible = true
    this.observer = new IntersectionObserver(([ entry ]) => { this.visible = entry.isIntersecting })
    this.observer.observe(this.canvasTarget)

    this.resize()
    if (this.reduceMotion) {
      this.placeCamera()
      this.renderer.render(this.scene, this.camera)
    } else {
      this.previous = performance.now()
      this.frame = requestAnimationFrame((now) => this.tick(now))
    }
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("pointermove", this.onPointer)
    window.removeEventListener("scroll", this.onScroll)
    this.observer?.disconnect()
    this.scene?.traverse((object) => {
      object.geometry?.dispose()
      object.material?.map?.dispose()
      object.material?.dispose()
    })
    this.renderer?.dispose()
  }

  buildHelix() {
    const THREE = this.THREE
    this.helix = new THREE.Group()
    this.helix.rotation.z = -0.12
    this.scene.add(this.helix)
    const geometry = new THREE.PlaneGeometry(1.92, 1.2)
    for (let i = 0; i < FRAMES; i++) {
      const material = new THREE.MeshBasicMaterial({ map: this.frameTexture(i), side: THREE.DoubleSide, transparent: true })
      const mesh = new THREE.Mesh(geometry, material)
      const angle = i * TURN
      mesh.position.set(Math.sin(angle) * RADIUS, (i - FRAMES / 2) * RISE, Math.cos(angle) * RADIUS)
      mesh.rotation.y = angle
      this.helix.add(mesh)
    }
  }

  buildDust() {
    const THREE = this.THREE
    const count = 700
    const positions = new Float32Array(count * 3)
    for (let i = 0; i < count; i++) {
      positions[i * 3] = (this.random() - 0.5) * 18
      positions[i * 3 + 1] = (this.random() - 0.5) * 11
      positions[i * 3 + 2] = (this.random() - 0.5) * 10
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))

    const sprite = document.createElement("canvas")
    sprite.width = sprite.height = 32
    const g = sprite.getContext("2d")
    const glow = g.createRadialGradient(16, 16, 0, 16, 16, 16)
    glow.addColorStop(0, "rgba(255,214,150,1)")
    glow.addColorStop(1, "rgba(255,214,150,0)")
    g.fillStyle = glow
    g.fillRect(0, 0, 32, 32)

    this.dust = new THREE.Points(geometry, new THREE.PointsMaterial({
      size: 0.07, map: new THREE.CanvasTexture(sprite), transparent: true, opacity: 0.55,
      depthWrite: false, blending: THREE.AdditiveBlending
    }))
    this.scene.add(this.dust)
  }

  // One film frame: sprocket holes, a painted 16:9 shot with vignette and grain, a badge and a timecode.
  frameTexture(i) {
    const canvas = document.createElement("canvas")
    canvas.width = 512
    canvas.height = 320
    const g = canvas.getContext("2d")
    g.fillStyle = "#0a0a0d"
    g.fillRect(0, 0, 512, 320)
    g.fillStyle = "#2a2722"
    for (let x = 8; x < 512; x += 26) { g.fillRect(x, 6, 13, 9); g.fillRect(x, 305, 13, 9) }

    g.save()
    g.beginPath()
    g.rect(16, 24, 480, 270)
    g.clip()
    g.translate(16, 24)
    const kinds = Object.keys(PAINTERS)
    PAINTERS[kinds[i % kinds.length]](g, 480, 270, this.random)

    const vignette = g.createRadialGradient(240, 135, 80, 240, 135, 300)
    vignette.addColorStop(0, "rgba(0,0,0,0)")
    vignette.addColorStop(1, "rgba(0,0,0,.6)")
    g.fillStyle = vignette
    g.fillRect(0, 0, 480, 270)
    const image = g.getImageData(0, 0, 480, 270)
    for (let p = 0; p < image.data.length; p += 4) {
      const noise = (this.random() - 0.5) * 22
      image.data[p] += noise; image.data[p + 1] += noise; image.data[p + 2] += noise
    }
    g.putImageData(image, 0, 0)

    const [ label, color ] = BADGES[i % BADGES.length]
    g.font = '500 13px "JetBrains Mono", Menlo, monospace'
    g.fillStyle = "rgba(10,10,13,.78)"
    g.fillRect(12, 12, g.measureText(label).width + 14, 22)
    g.fillStyle = color
    g.fillText(label, 19, 28)
    const seconds = i * 9
    const code = `SC ${String(i + 1).padStart(2, "0")}  00:${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`
    g.fillStyle = "rgba(10,10,13,.7)"
    g.fillRect(12, 238, g.measureText(code).width + 14, 22)
    g.fillStyle = "#ede6d8"
    g.fillText(code, 19, 254)
    g.restore()

    const texture = new this.THREE.CanvasTexture(canvas)
    texture.anisotropy = 4
    return texture
  }

  resize() {
    const { width, height } = this.canvasTarget.getBoundingClientRect()
    if (!width) return
    this.renderer.setSize(width, height, false)
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    const wide = width > 900
    this.helix.position.set(wide ? 2.9 : 0, wide ? 0 : 1.2, 0)
    this.camera.position.z = wide ? 10 : 12.5
    if (this.reduceMotion) { this.placeCamera(); this.renderer.render(this.scene, this.camera) }
  }

  placeCamera() {
    this.camera.position.x = this.pointer.smoothX * 1.6
    this.camera.position.y = -this.pointer.smoothY
    this.camera.lookAt(this.helix.position.x * 0.55, 0, 0)
  }

  tick(now) {
    this.frame = requestAnimationFrame((t) => this.tick(t))
    const dt = Math.min((now - this.previous) / 1000, 0.05)
    this.previous = now
    if (this.hasTimecodeTarget) this.timecodeTarget.textContent = timecode(now - this.startedAt)
    if (!this.visible) return

    this.scrollBoost *= 0.92
    this.rotation += dt * 0.12 + this.scrollBoost
    this.helix.rotation.y = this.rotation
    // Frames rise up the helix and wrap to the bottom, like film feeding through.
    this.helix.children.forEach((mesh, i) => {
      mesh.position.y = ((i * RISE + now * 0.00012) % (FRAMES * RISE)) - FRAMES * RISE / 2
    })
    this.pointer.smoothX += (this.pointer.x - this.pointer.smoothX) * 0.04
    this.pointer.smoothY += (this.pointer.y - this.pointer.smoothY) * 0.04
    this.placeCamera()
    this.dust.rotation.y = now * 0.00002
    this.renderer.render(this.scene, this.camera)
  }
}

function seededRandom(seed) {
  let s = seed
  return () => (s = (s * 16807) % 2147483647) / 2147483647
}

function timecode(ms) {
  const frames = Math.floor(ms / (1000 / 30))
  const seconds = Math.floor(frames / 30)
  const pad = (n) => String(n).padStart(2, "0")
  return `${pad(Math.floor(seconds / 3600))}:${pad(Math.floor(seconds / 60) % 60)}:${pad(seconds % 60)}:${pad(frames % 30)}`
}

function sky(g, w, h, top, bottom) {
  const gradient = g.createLinearGradient(0, 0, 0, h)
  gradient.addColorStop(0, top)
  gradient.addColorStop(1, bottom)
  g.fillStyle = gradient
  g.fillRect(0, 0, w, h)
}

// Each painter draws one kind of archive shot into a w×h frame.
const PAINTERS = {
  sea(g, w, h, random) {
    sky(g, w, h * 0.62, "#3a2a3e", "#e59a4a")
    g.fillStyle = "#f7d08a"; g.beginPath(); g.arc(w * 0.68, h * 0.56, 26, 0, Math.PI * 2); g.fill()
    g.fillStyle = "#1b2230"; g.fillRect(0, h * 0.62, w, h)
    g.strokeStyle = "rgba(247,208,138,.35)"
    for (let i = 0; i < 14; i++) {
      const y = h * 0.65 + i * 7
      g.beginPath(); g.moveTo(w * 0.55 + random() * 30, y); g.lineTo(w * 0.82 - random() * 30, y); g.stroke()
    }
    g.fillStyle = "#0d0f15"
    const x = w * 0.28, y = h * 0.62
    g.beginPath(); g.moveTo(x - 70, y - 12); g.lineTo(x + 80, y - 12); g.lineTo(x + 62, y + 4); g.lineTo(x - 58, y + 4); g.fill()
    for (const [ dx, mast ] of [ [ -34, 92 ], [ 8, 112 ], [ 48, 80 ] ]) {
      g.fillRect(x + dx, y - 12 - mast, 3, mast)
      g.beginPath(); g.moveTo(x + dx + 3, y - 10 - mast); g.lineTo(x + dx + 34, y - 30); g.lineTo(x + dx + 3, y - 26); g.fill()
    }
  },
  skyline(g, w, h, random) {
    sky(g, w, h, "#0c1424", "#2b3550")
    g.fillStyle = "#fff"
    for (let i = 0; i < 60; i++) g.fillRect(random() * w, random() * h * 0.5, 1.2, 1.2)
    let x = 0
    while (x < w) {
      const bw = 20 + random() * 34, bh = 40 + random() * 120
      g.fillStyle = "#0a0d16"; g.fillRect(x, h - bh, bw, bh)
      g.fillStyle = "rgba(240,180,90,.75)"
      for (let wy = h - bh + 8; wy < h - 6; wy += 10) {
        for (let wx = x + 4; wx < x + bw - 4; wx += 7) if (random() > 0.62) g.fillRect(wx, wy, 3, 4)
      }
      x += bw + 2
    }
  },
  figure(g, w, h) {
    sky(g, w, h, "#4b2a2a", "#f1a95a")
    g.fillStyle = "#ffe2a8"; g.beginPath(); g.arc(w * 0.5, h * 0.7, 60, 0, Math.PI * 2); g.fill()
    g.fillStyle = "#1a1214"
    g.beginPath(); g.moveTo(0, h * 0.82); g.quadraticCurveTo(w * 0.5, h * 0.7, w, h * 0.84); g.lineTo(w, h); g.lineTo(0, h); g.fill()
    const cx = w * 0.5, base = h * 0.78
    g.beginPath(); g.arc(cx, base - 92, 13, 0, Math.PI * 2); g.fill()
    g.beginPath(); g.moveTo(cx - 30, base); g.lineTo(cx - 24, base - 64); g.quadraticCurveTo(cx, base - 82, cx + 24, base - 64); g.lineTo(cx + 30, base); g.fill()
  },
  temple(g, w, h) {
    sky(g, w, h, "#a8936b", "#d9c7a0")
    g.fillStyle = "#4a3a26"
    const x0 = w * 0.2, x1 = w * 0.8, top = h * 0.3
    g.beginPath(); g.moveTo(x0 - 10, top); g.lineTo(w * 0.5, top - 44); g.lineTo(x1 + 10, top); g.fill()
    g.fillRect(x0 - 10, top, x1 - x0 + 20, 12)
    for (let i = 0; i < 8; i++) g.fillRect(x0 + i * (x1 - x0) / 7.6, top + 16, 12, h * 0.5)
    g.fillRect(x0 - 20, top + 16 + h * 0.5, x1 - x0 + 40, 14)
  },
  dome(g, w, h, random) {
    sky(g, w, h, "#22304a", "#d98a52")
    g.fillStyle = "#5c3a22"
    g.beginPath(); g.moveTo(0, h * 0.82)
    for (let x = 0; x <= w; x += 40) g.quadraticCurveTo(x + 20, h * (0.74 + random() * 0.08), x + 40, h * 0.82)
    g.lineTo(w, h); g.lineTo(0, h); g.fill()
    g.fillStyle = "#140f12"
    const cx = w * 0.52, b = h * 0.8
    g.fillRect(cx - 70, b - 50, 140, 50)
    g.beginPath(); g.arc(cx, b - 50, 46, Math.PI, 0); g.fill()
    g.fillRect(cx - 1.5, b - 118, 3, 24)
    for (const dx of [ -112, 112 ]) {
      g.fillRect(cx + dx - 6, b - 120, 12, 120)
      g.beginPath(); g.moveTo(cx + dx - 8, b - 120); g.lineTo(cx + dx, b - 140); g.lineTo(cx + dx + 8, b - 120); g.fill()
    }
  },
  mountains(g, w, h, random) {
    sky(g, w, h, "#28344a", "#9aa7b4")
    ;[ "#57657a", "#3b4759", "#232c3a" ].forEach((color, k) => {
      g.fillStyle = color
      g.beginPath(); g.moveTo(0, h)
      let y = h * (0.45 + k * 0.13)
      for (let x = 0; x <= w; x += 30) {
        y += (random() - 0.5) * 40
        g.lineTo(x, Math.max(h * 0.25, Math.min(h * 0.9, y)))
      }
      g.lineTo(w, h); g.fill()
    })
  },
  document(g, w, h, random) {
    g.fillStyle = "#d9c9a6"; g.fillRect(0, 0, w, h)
    g.strokeStyle = "rgba(60,40,20,.7)"; g.lineWidth = 1.4
    for (let y = 40; y < h - 30; y += 18) {
      g.beginPath()
      let x = 40
      g.moveTo(x, y)
      const end = w - 50 - random() * 60
      while (x < end) { x += 6; g.lineTo(x, y + Math.sin(x * 0.7) * 2.2) }
      g.stroke()
    }
    g.strokeStyle = "rgba(140,40,30,.8)"; g.lineWidth = 3
    g.beginPath(); g.arc(w - 80, h - 70, 30, 0, Math.PI * 2); g.stroke()
  },
  storm(g, w, h, random) {
    sky(g, w, h, "#151a22", "#3c4654")
    g.fillStyle = "#0c0f14"; g.fillRect(0, h * 0.78, w, h)
    g.fillRect(w * 0.7, h * 0.38, 18, h * 0.4)
    g.fillStyle = "#f4c46a"; g.fillRect(w * 0.7 - 2, h * 0.34, 22, 12)
    g.fillStyle = "rgba(244,196,106,.18)"
    g.beginPath(); g.moveTo(w * 0.7 + 9, h * 0.4); g.lineTo(0, h * 0.25); g.lineTo(0, h * 0.5); g.fill()
    g.strokeStyle = "rgba(200,210,230,.28)"
    for (let i = 0; i < 90; i++) {
      const x = random() * w, y = random() * h
      g.beginPath(); g.moveTo(x, y); g.lineTo(x - 6, y + 16); g.stroke()
    }
  }
}
