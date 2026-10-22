import { Controller } from "@hotwired/stimulus"

// Keeps the message list scrolled to the newest message, including when Turbo
// Streams append a broadcast message after the page has loaded.
export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
