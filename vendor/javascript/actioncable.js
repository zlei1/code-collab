const DEFAULT_PROTOCOLS = ["actioncable-v1-json", "actioncable-v1-msgpack"]

function resolveCableUrl() {
  const meta = document.querySelector('meta[name="action-cable-url"]')
  let url = meta && meta.content ? meta.content : "/cable"
  if (url.startsWith("ws://") || url.startsWith("wss://")) return url
  const protocol = window.location.protocol === "https:" ? "wss" : "ws"
  if (url.startsWith("//")) return `${protocol}:${url}`
  if (url.startsWith("/")) return `${protocol}://${window.location.host}${url}`
  return url
}

class Subscription {
  constructor(consumer, identifier, callbacks = {}) {
    this.consumer = consumer
    this.identifier = identifier
    this.callbacks = callbacks
  }

  perform(action, data = {}) {
    this.consumer._send({
      command: "message",
      identifier: this.identifier,
      data: JSON.stringify({ ...data, action }),
    })
  }

  received(data) {
    if (this.callbacks.received) this.callbacks.received(data)
  }

  connected() {
    if (this.callbacks.connected) this.callbacks.connected()
  }

  disconnected() {
    if (this.callbacks.disconnected) this.callbacks.disconnected()
  }
}

class Subscriptions {
  constructor(consumer) {
    this.consumer = consumer
    this.subscriptions = []
  }

  create(identifier, callbacks = {}) {
    const id = typeof identifier === "string" ? identifier : JSON.stringify(identifier)
    const subscription = new Subscription(this.consumer, id, callbacks)
    this.subscriptions.push(subscription)
    this.consumer._subscribe(subscription)
    return subscription
  }

  remove(subscription) {
    this.subscriptions = this.subscriptions.filter((sub) => sub !== subscription)
    this.consumer._unsubscribe(subscription)
  }

  find(identifier) {
    return this.subscriptions.find((sub) => sub.identifier === identifier)
  }
}

class Consumer {
  constructor(url = resolveCableUrl()) {
    this.url = url
    this.subscriptions = new Subscriptions(this)
    this.connected = false
    this._connect()
  }

  _connect() {
    this.webSocket = new WebSocket(this.url, DEFAULT_PROTOCOLS)
    this.webSocket.onopen = () => {
      this.connected = true
      this.subscriptions.subscriptions.forEach((sub) => this._subscribe(sub))
    }
    this.webSocket.onmessage = (event) => this._handleMessage(event.data)
    this.webSocket.onclose = () => {
      this.connected = false
      this.subscriptions.subscriptions.forEach((sub) => sub.disconnected())
    }
  }

  _handleMessage(raw) {
    let data
    try {
      data = JSON.parse(raw)
    } catch (_) {
      return
    }

    if (data.type === "ping" || data.type === "welcome") return

    if (data.type === "confirm_subscription") {
      const subscription = this.subscriptions.find(data.identifier)
      if (subscription) subscription.connected()
      return
    }

    if (data.type === "reject_subscription") return

    if (data.identifier && data.message) {
      const subscription = this.subscriptions.find(data.identifier)
      if (subscription) subscription.received(data.message)
    }
  }

  _send(payload) {
    if (!this.webSocket || this.webSocket.readyState !== WebSocket.OPEN) return
    this.webSocket.send(JSON.stringify(payload))
  }

  _subscribe(subscription) {
    this._send({ command: "subscribe", identifier: subscription.identifier })
  }

  _unsubscribe(subscription) {
    this._send({ command: "unsubscribe", identifier: subscription.identifier })
  }
}

export function createConsumer(url) {
  return new Consumer(url)
}
