import { Controller } from "@hotwired/stimulus"

// A small options menu behind a button: opens and closes on the button, and closes on Escape or a
// click anywhere else.
export default class extends Controller {
  static targets = ["button", "list"]

  connect() {
    this.closeOutside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.closeOnEscape = (event) => {
      if (event.key !== "Escape") return
      this.close()
      this.buttonTarget.focus()
    }
  }

  disconnect() {
    this.close()
  }

  toggle() {
    this.listTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.listTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.closeOutside)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  close() {
    this.listTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.closeOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
  }
}
