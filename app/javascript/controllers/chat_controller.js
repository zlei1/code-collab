import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"
import { cableConnected, cableDisconnected, createCableToken } from "lib/cable_status"

export default class extends Controller {
  static values = { roomId: Number, currentUserId: Number }
  static targets = ["messages", "input", "sendButton"]

  connect() {
    this.consumer = getConsumer()
    this.cableStatusToken = createCableToken("chat")
    this.seenMessageIds = new Set()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "RoomChatChannel", room_id: this.roomIdValue },
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

  send(event) {
    event.preventDefault()
    if (this.isDisconnected) return
    const content = this.inputTarget.value.trim()
    if (!content) return
    this.subscription.perform("message", { content })
    this.inputTarget.value = ""
  }

  received(data) {
    if (data.type === "history") {
      data.messages.forEach((message) => this.appendMessage(message))
      return
    }
    if (data.type === "message") {
      this.appendMessage(data.message)
    }
  }

  appendMessage(message) {
    if (message && message.id && this.seenMessageIds.has(message.id)) return
    if (message && message.id) this.seenMessageIds.add(message.id)
    const isCurrentUser = message.user_id === this.currentUserIdValue
    const item = document.createElement("div")
    item.className = `chat-message ${isCurrentUser ? 'current-user' : 'other-user'}`

    const avatar = document.createElement("div")
    avatar.className = "chat-message-avatar"
    avatar.textContent = this.initials(message.user)

    const body = document.createElement("div")
    body.className = "chat-message-body"

    const meta = document.createElement("div")
    meta.className = "chat-message-meta"

    const name = document.createElement("span")
    name.className = "chat-message-name"
    name.textContent = message.user

    const time = document.createElement("span")
    time.className = "chat-message-time"
    time.textContent = this.formatTime(message.created_at)

    const content = document.createElement("div")
    content.className = "chat-message-content"
    content.textContent = message.content

    meta.appendChild(name)
    if (time.textContent) meta.appendChild(time)
    body.appendChild(meta)
    body.appendChild(content)
    item.appendChild(avatar)
    item.appendChild(body)
    this.messagesTarget.appendChild(item)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  initials(name) {
    if (!name) return "?"
    const letters = name.match(/[A-Za-z0-9]/g) || []
    return letters.slice(0, 2).join("").toUpperCase() || "?"
  }

  formatTime(iso) {
    if (!iso) return ""
    const date = new Date(iso)
    if (Number.isNaN(date.getTime())) return ""
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }

  setDisconnected(state) {
    this.isDisconnected = state
    if (this.hasInputTarget) {
      this.inputTarget.disabled = state
      this.inputTarget.placeholder = state ? "Connection lost..." : "Type a message..."
    }
    if (this.hasSendButtonTarget) {
      this.sendButtonTarget.disabled = state
    }
    this.element.classList.toggle("is-disconnected", state)
  }
}
