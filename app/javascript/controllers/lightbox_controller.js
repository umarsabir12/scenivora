import { Controller } from "@hotwired/stimulus"

// Shows an image full size in a dialog on the same page. Escape, the close button or a click
// anywhere on the dialog closes it.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
