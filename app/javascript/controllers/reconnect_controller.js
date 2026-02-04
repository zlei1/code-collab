import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    this.visible = false
    this.retryTimer = null
    this.onDisconnected = () => this.show()
    this.onConnected = () => this.hide()
    window.addEventListener("cable:disconnected", this.onDisconnected)
    window.addEventListener("cable:connected", this.onConnected)
  }

  disconnect() {
    window.removeEventListener("cable:disconnected", this.onDisconnected)
    window.removeEventListener("cable:connected", this.onConnected)
    this.stopRetry()
  }

  show() {
    if (this.visible) return
    this.visible = true
    this.element.classList.remove("is-hidden")
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = "Connection lost. Reconnecting..."
    }
    this.startRetry()
  }

  hide() {
    if (!this.visible) return
    this.visible = false
    this.element.classList.add("is-hidden")
    this.stopRetry()
  }

  startRetry() {
    if (this.retryTimer) return
    const consumer = getConsumer()
    this.retryTimer = setInterval(() => {
      if (consumer && consumer.reconnect) consumer.reconnect()
    }, 2000)
  }

  stopRetry() {
    if (!this.retryTimer) return
    clearInterval(this.retryTimer)
    this.retryTimer = null
  }
}
