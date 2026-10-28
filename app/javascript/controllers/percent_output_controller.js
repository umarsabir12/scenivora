import { Controller } from "@hotwired/stimulus"

// Shows a range input's value as a percentage next to it.
export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    this.update()
  }

  update() {
    this.outputTarget.textContent = `${this.inputTarget.value}%`
  }
}
