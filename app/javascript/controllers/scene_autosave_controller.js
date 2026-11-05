import { Controller } from "@hotwired/stimulus"

// Saves a storyboard scene's narration shortly after the user stops typing, and on blur. Editing one
// scene moves the start times of the scenes after it, so the answer's new times are written into
// the page instead of reloading it, which would interrupt typing.
export default class extends Controller {
  static targets = ["field", "status"]
  static values = { url: String, delay: { type: Number, default: 800 } }

  connect() {
    this.savedText = this.fieldTarget.value
  }

  disconnect() {
    // The page morphs after other actions; flush pending edits first.
    this.save()
  }

  queue() {
    this.setStatus("Unsaved")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  async save() {
    clearTimeout(this.timer)
    const text = this.fieldTarget.value
    if (text === this.savedText) return

    this.setStatus("Saving…")
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ scene: { text } })
      })
      const answer = await response.json()
      if (!response.ok) throw new Error(answer.error || `Save failed with ${response.status}`)

      this.savedText = text
      this.setStatus("Saved")
      this.showTimings(answer)
    } catch (error) {
      this.setStatus(error.message.startsWith("A scene") ? error.message : "Couldn't save. It will retry on your next change.")
    }
  }

  showTimings({ starts, length }) {
    Object.entries(starts || {}).forEach(([id, time]) => {
      document.querySelectorAll(`[data-scene-start="${id}"]`).forEach((element) => { element.textContent = time })
    })
    if (length) document.querySelectorAll("[data-storyboard-length]").forEach((element) => { element.textContent = length })
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
