import { Controller } from "@hotwired/stimulus"

// Replays the landing page's example production log, one step every 900 ms. The page renders the
// finished run, so it reads correctly without JavaScript or with reduced motion.
export default class extends Controller {
  static targets = ["item", "bar", "title", "clock"]

  disconnect() {
    clearInterval(this.timer)
  }

  replay(event) {
    event.preventDefault()
    clearInterval(this.timer)
    const last = this.itemTargets.length - 1
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return this.show(last)

    let step = 0
    this.show(step)
    this.timer = setInterval(() => {
      this.show(++step)
      if (step >= last) clearInterval(this.timer)
    }, 900)
  }

  show(current) {
    const last = this.itemTargets.length - 1
    this.itemTargets.forEach((item, i) => {
      const done = i < current || current === last
      const status = item.querySelector(".s")
      item.classList.toggle("on", i === current)
      item.classList.toggle("wait", i > current)
      status.className = "s " + (done ? "done" : i === current ? "run" : "wait")
      status.textContent = done ? "DONE" : i === current ? "RUNNING" : "QUEUED"
    })
    this.barTarget.style.width = `${(current + 1) / this.itemTargets.length * 100}%`
    this.clockTarget.textContent = this.itemTargets[current].dataset.time
    this.titleTarget.textContent = current === last ? "Storyboard ready" : "Making your video…"
  }
}
