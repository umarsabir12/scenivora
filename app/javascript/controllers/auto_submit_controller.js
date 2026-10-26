import { Controller } from "@hotwired/stimulus"

// Submits the form as soon as a file is chosen.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
