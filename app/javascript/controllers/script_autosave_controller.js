import { Controller } from "@hotwired/stimulus"

// Saves the script textarea shortly after the user stops typing, and on blur.
export default class extends Controller {
  static targets = ["field", "status"]
  static values = { url: String, delay: { type: Number, default: 800 } }

  connect() {
    this.savedBody = this.fieldTarget.value
  }

  disconnect() {
    // The panel is replaced on Rewrite or regeneration; flush pending edits first.
    this.save()
  }

  queue() {
    this.setStatus("Unsaved changes")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  async save() {
    clearTimeout(this.timer)
    const body = this.fieldTarget.value
    if (body === this.savedBody) return

    this.setStatus("Saving…")
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ script: { body } })
      })
      if (!response.ok) throw new Error(`Save failed with ${response.status}`)

      this.savedBody = body
      this.setStatus("Saved")
    } catch {
      this.setStatus("Couldn't save. Your edits will retry on the next change.")
    }
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
