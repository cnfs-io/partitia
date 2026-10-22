import { Controller } from "@hotwired/stimulus"

// Clears the message form after a successful Turbo submit, so the input is
// empty and refocused for the next message.
export default class extends Controller {
  reset(event) {
    if (event.detail.success) {
      this.element.reset()
      this.element.querySelector("input[type=text]")?.focus()
    }
  }
}
