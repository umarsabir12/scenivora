import { Controller } from "@hotwired/stimulus"

// Copies the source field's text to the clipboard and briefly confirms on the button.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const label = this.buttonTarget.textContent
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
      this.buttonTarget.textContent = "Copied"
    } catch {
      this.buttonTarget.textContent = "Copy failed"
    }
    setTimeout(() => { this.buttonTarget.textContent = label }, 1500)
  }
}
