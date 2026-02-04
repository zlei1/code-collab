import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 4000 },
    dismissDuration: { type: Number, default: 400 },
  }

  connect() {
    this.timeouts = []
    this.scheduleDismiss()
  }

  disconnect() {
    this.clearTimeouts()
  }

  scheduleDismiss() {
    const flashes = this.element.querySelectorAll(".flash")
    flashes.forEach((flash) => {
      const timeoutId = window.setTimeout(() => {
        flash.classList.add("is-hiding")
        const removeId = window.setTimeout(() => {
          flash.remove()
        }, this.dismissDurationValue)
        this.timeouts.push(removeId)
      }, this.timeoutValue)
      this.timeouts.push(timeoutId)
    })
  }

  clearTimeouts() {
    if (!this.timeouts) return
    this.timeouts.forEach((timeoutId) => window.clearTimeout(timeoutId))
    this.timeouts = []
  }
}
