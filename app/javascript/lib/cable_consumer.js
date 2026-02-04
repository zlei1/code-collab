import { createConsumer } from "@rails/actioncable"

class ManagedSubscription {
  constructor(manager, identifier, callbacks = {}) {
    this.manager = manager
    this.identifier = identifier
    this.callbacks = callbacks
    this.inner = null
  }

  attach(inner) {
    this.inner = inner
  }

  detach() {
    if (this.inner) {
      this.manager._consumer.subscriptions.remove(this.inner)
      this.inner = null
    }
  }

  perform(action, data = {}) {
    if (!this.inner) return
    this.inner.perform(action, data)
  }
}

class ManagedConsumer {
  constructor() {
    this._consumer = null
    this._managed = new Set()
    this._reconnectTimer = null
    this._reconnectAttempt = 0
    this._socketConnected = false

    this.subscriptions = {
      create: (identifier, callbacks = {}) => this._create(identifier, callbacks),
      remove: (subscription) => this._remove(subscription),
    }

    this._connect()
  }

  _connect() {
    this._consumer = createConsumer()
    this._wrapSocketHandlers(this._consumer)
    this._managed.forEach((managed) => this._attach(managed))
  }

  reconnect() {
    const socket = this._consumer && this._consumer.webSocket
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
      return
    }
    this._connect()
  }

  _wrapSocketHandlers(consumer) {
    const socket = consumer.webSocket
    if (!socket) return
    const originalOpen = socket.onopen
    const originalClose = socket.onclose
    socket.onopen = (event) => {
      if (originalOpen) originalOpen(event)
      this._onSocketOpen()
    }
    socket.onclose = (event) => {
      if (originalClose) originalClose(event)
      this._onSocketClose()
    }
  }

  _onSocketOpen() {
    if (!this._socketConnected) {
      this._socketConnected = true
      window.dispatchEvent(new CustomEvent("cable:connected"))
    }
    this._reconnectAttempt = 0
    if (this._reconnectTimer) {
      clearTimeout(this._reconnectTimer)
      this._reconnectTimer = null
    }
  }

  _onSocketClose() {
    if (this._socketConnected) {
      this._socketConnected = false
      window.dispatchEvent(new CustomEvent("cable:disconnected"))
    }
    if (this._managed.size === 0) return
    this._scheduleReconnect()
  }

  _scheduleReconnect() {
    if (this._reconnectTimer) return
    const delay = Math.min(1000 * Math.pow(2, this._reconnectAttempt), 10000)
    this._reconnectTimer = setTimeout(() => {
      this._reconnectTimer = null
      this._reconnectAttempt += 1
      this._connect()
    }, delay)
  }

  _wrapCallbacks(managed) {
    const callbacks = managed.callbacks || {}
    return {
      received: callbacks.received,
      connected: () => {
        if (callbacks.connected) callbacks.connected()
      },
      disconnected: () => {
        if (callbacks.disconnected) callbacks.disconnected()
      },
    }
  }

  _attach(managed) {
    if (!this._consumer) return
    const inner = this._consumer.subscriptions.create(managed.identifier, this._wrapCallbacks(managed))
    managed.attach(inner)
  }

  _create(identifier, callbacks = {}) {
    const managed = new ManagedSubscription(this, identifier, callbacks)
    this._managed.add(managed)
    if (this._consumer) this._attach(managed)
    return managed
  }

  _remove(managed) {
    if (!managed) return
    if (this._managed.has(managed)) {
      managed.detach()
      this._managed.delete(managed)
    }
  }
}

let consumer = null

export function getConsumer() {
  if (!consumer) consumer = new ManagedConsumer()
  return consumer
}
