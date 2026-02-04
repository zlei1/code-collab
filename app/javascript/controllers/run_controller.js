import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"
import { cableConnected, cableDisconnected, createCableToken } from "lib/cable_status"

export default class extends Controller {
  static values = { roomSlug: String, roomId: Number }
  static targets = ["output", "button"]

  connect() {
    this.consumer = getConsumer()
    this.cableStatusToken = createCableToken("run")
    this.subscription = this.consumer.subscriptions.create(
      { channel: "RoomRunChannel", room_id: this.roomIdValue },
      {
        received: (data) => this.received(data),
        connected: () => cableConnected(this.cableStatusToken),
        disconnected: () => cableDisconnected(this.cableStatusToken),
      }
    )
    this.isDisconnected = false
    this.handleCableDisconnected = () => this.setDisconnected(true)
    this.handleCableConnected = () => this.setDisconnected(false)
    window.addEventListener("cable:disconnected", this.handleCableDisconnected)
    window.addEventListener("cable:connected", this.handleCableConnected)
  }

  disconnect() {
    if (this.subscription) this.consumer.subscriptions.remove(this.subscription)
    this.subscription = null
    cableConnected(this.cableStatusToken)
    window.removeEventListener("cable:disconnected", this.handleCableDisconnected)
    window.removeEventListener("cable:connected", this.handleCableConnected)
  }

  async start() {
    if (this.isDisconnected) return
    this.outputTarget.textContent = "Running..."
    const response = await fetch(`/rooms/${this.roomSlugValue}/run`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
      },
    })
    if (!response.ok) {
      this.outputTarget.textContent = "Failed to start run."
      return
    }
  }

  received(data) {
    if (data.type === "run") {
      this.outputTarget.textContent = `Queued run ${data.run_id}`
      return
    }
    if (data.type === "status") {
      this.outputTarget.textContent = `Status: ${data.status}`
      return
    }
    if (data.type === "result") {
      const parts = []
      parts.push(`Status: ${data.status}`)
      if (data.stdout) parts.push(`\nSTDOUT:\n${data.stdout}`)
      if (data.stderr) parts.push(`\nSTDERR:\n${data.stderr}`)
      if (data.exit_code !== undefined && data.exit_code !== null) {
        parts.push(`\nExit code: ${data.exit_code}`)
      }
      this.outputTarget.textContent = parts.join("\n")
    }
  }

  csrfToken() {
    const meta = document.querySelector("meta[name='csrf-token']")
    return meta ? meta.getAttribute("content") : ""
  }

  setDisconnected(state) {
    this.isDisconnected = state
    this.element.classList.toggle("is-disconnected", state)
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = state
    }
  }
}
