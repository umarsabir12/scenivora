import { Controller } from "@hotwired/stimulus"

// Shows or hides the password in a sign-in or sign-up field.
export default class extends Controller {
  static targets = ["input", "button"]

  toggle() {
    const hidden = this.inputTarget.type === "password"
    this.inputTarget.type = hidden ? "text" : "password"
    this.buttonTarget.textContent = hidden ? "Hide" : "Show"
    this.buttonTarget.setAttribute("aria-label", hidden ? "Hide password" : "Show password")
  }
}
