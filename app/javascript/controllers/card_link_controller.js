import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Opens a scene in the swap panel without reloading the page: marks the card as current, then
// loads only the panel's frame. A click on the card's own links, buttons or form fields, or a text
// selection, is left alone. On narrow screens the panel sits below the list, so it is scrolled into view.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    if (event.target.closest("a, button, input, label, select, textarea, form")) return
    if (window.getSelection()?.toString()) return

    this.select(event)
  }

  select(event) {
    document.querySelectorAll("[data-controller~='card-link']").forEach((card) => card.setAttribute("aria-current", "false"))
    this.element.setAttribute("aria-current", "true")

    Turbo.visit(event.params?.url || this.urlValue, { frame: "swap_panel" })

    const panel = document.getElementById("swap_panel")
    if (panel && window.matchMedia("(max-width: 1023px)").matches) panel.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
