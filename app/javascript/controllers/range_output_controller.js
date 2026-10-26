import { Controller } from "@hotwired/stimulus"

// Shows the current speed next to a range input, and applies it to sample previews.
// Previews play at the chosen speed in the browser, so moving the slider costs nothing.
export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    this.update()
  }

  update() {
    const speed = Number(this.inputTarget.value)
    this.outputTarget.textContent = `${speed.toFixed(2)}x`
    this.element.querySelectorAll("audio[data-sample-player]").forEach((audio) => {
      audio.playbackRate = speed
    })
  }
}
