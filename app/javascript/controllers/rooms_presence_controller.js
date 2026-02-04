import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"
import { cableConnected, cableDisconnected, createCableToken } from "lib/cable_status"

export default class extends Controller {
  static values = { roomIds: String }
  static targets = ["list"]

  connect() {
    this.consumer = getConsumer()
    this.subscriptions = new Map()
    this.roomLists = new Map()
    this.handleCableDisconnected = () => this.renderDisconnected()
    this.listTargets.forEach((element) => {
      const roomId = element.dataset.roomId
      if (roomId) this.roomLists.set(roomId, element)
    })
    this.roomIds().forEach((roomId) => this.subscribeToRoom(roomId))
    window.addEventListener("cable:disconnected", this.handleCableDisconnected)
  }

  disconnect() {
    this.subscriptions.forEach((entry) => {
      this.consumer.subscriptions.remove(entry.subscription)
      cableConnected(entry.statusToken)
    })
    this.subscriptions.clear()
    this.roomLists.clear()
    window.removeEventListener("cable:disconnected", this.handleCableDisconnected)
  }

  roomIds() {
    if (!this.hasRoomIdsValue) return []
    return this.roomIdsValue
      .split(",")
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
  }

  subscribeToRoom(roomId) {
    if (this.subscriptions.has(roomId)) return
    const statusToken = createCableToken(`presence-${roomId}`)
    const subscription = this.consumer.subscriptions.create(
      { channel: "RoomSignalChannel", room_id: roomId, presence_only: true },
      {
        received: (data) => this.handlePresence(roomId, data),
        connected: () => cableConnected(statusToken),
        disconnected: () => cableDisconnected(statusToken),
      }
    )
    this.subscriptions.set(roomId, { subscription, statusToken })
  }

  handlePresence(roomId, data) {
    if (!data || data.type !== "presence") return
    const users = Array.isArray(data.users) ? data.users : []
    this.renderUsers(roomId, users)
  }

  renderUsers(roomId, users) {
    const list = this.roomLists.get(String(roomId))
    if (!list) return

    list.innerHTML = ""

    if (users.length === 0) {
      const empty = document.createElement("span")
      empty.className = "room-online-empty"
      empty.textContent = "No one online"
      list.appendChild(empty)
      return
    }

    users.forEach((user) => {
      const chip = document.createElement("span")
      chip.className = "room-online-chip"

      const dot = document.createElement("span")
      dot.className = "room-online-dot"
      if (user.has_media) dot.classList.add("is-media")

      const label = document.createElement("span")
      label.textContent = user.label || user.email || "Online user"

      chip.appendChild(dot)
      chip.appendChild(label)
      list.appendChild(chip)
    })
  }

  renderDisconnected() {
    this.roomLists.forEach((list) => {
      list.innerHTML = ""
      const empty = document.createElement("span")
      empty.className = "room-online-empty"
      empty.textContent = "Reconnecting..."
      list.appendChild(empty)
    })
  }
}
