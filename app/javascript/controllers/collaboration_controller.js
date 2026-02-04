import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"
import { cableConnected, cableDisconnected, createCableToken } from "lib/cable_status"

class ActionCableAdapter {
  constructor() {
    this.callbacks = {}
    this.subscription = null
    this.clientId = null
  }

  setSubscription(subscription) {
    this.subscription = subscription
  }

  setClientId(clientId) {
    this.clientId = clientId
  }

  registerCallbacks(callbacks) {
    this.callbacks = callbacks
  }

  sendOperation(revision, operation, selection) {
    if (!this.subscription) return
    this.subscription.perform("operation", { revision, operation, selection })
  }

  sendSelection(selection) {
    if (!this.subscription) return
    this.subscription.perform("selection", { selection })
  }

  receive(data) {
    switch (data.type) {
      case "ack":
        if (data.client_id && data.client_id !== this.clientId) return
        this.trigger("ack")
        break
      case "operation":
        if (data.client_id === this.clientId) return
        this.trigger("operation", data.operation)
        this.trigger("selection", data.client_id, data.selection)
        break
      case "selection":
        if (data.client_id === this.clientId) return
        this.trigger("selection", data.client_id, data.selection)
        break
      case "client_left":
        this.trigger("client_left", data.client_id)
        break
      case "set_name":
        this.trigger("set_name", data.client_id, data.name)
        break
      case "resync":
        if (data.client_id && data.client_id !== this.clientId) return
        this.trigger("resync")
        break
      case "clients":
        this.trigger("clients", data.clients)
        break
      case "reconnect":
        this.trigger("reconnect")
        break
      default:
        break
    }
  }

  trigger(event, ...args) {
    const action = this.callbacks && this.callbacks[event]
    if (action) action.apply(this, args)
  }
}

export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this.adapter = new ActionCableAdapter()
    this.consumer = getConsumer()
    this.cableStatusToken = createCableToken("collab")
    this.hasConnected = false
    this.editor = null
    this.editorAdapter = null
    this.editorClient = null
    this.subscription = this.consumer.subscriptions.create(
      { channel: "CollaborationChannel" },
      {
        received: (data) => this.received(data),
        connected: () => {
          if (this.hasConnected) {
            this.requestResync()
          } else {
            this.hasConnected = true
          }
          cableConnected(this.cableStatusToken)
        },
        disconnected: () => cableDisconnected(this.cableStatusToken),
      }
    )
    this.adapter.setSubscription(this.subscription)
    this.pendingDoc = null
    this.dependencyTimer = null
    this.dependencyStart = null
    this.dependencyWarned = false
    this.waitForDependencies()
  }

  disconnect() {
    if (this.subscription) this.consumer.subscriptions.remove(this.subscription)
    this.subscription = null
    this.consumer = null
    cableConnected(this.cableStatusToken)
    this.hasConnected = false
    if (this.dependencyTimer) clearTimeout(this.dependencyTimer)
    this.dependencyTimer = null
  }

  received(data) {
    if (data.type === "resync") {
      if (data.client_id && data.client_id !== this.adapter.clientId) return
      this.requestResync()
      return
    }
    if (data.type === "doc") {
      this.adapter.setClientId(data.client_id)
      if (window.CodeMirror && window.ot) {
        this.initializeEditor(data)
      } else {
        this.pendingDoc = data
        this.waitForDependencies()
      }
      return
    }
    this.adapter.receive(data)
  }

  waitForDependencies() {
    if (this.editorClient) return
    if (window.CodeMirror && window.ot) {
      if (this.pendingDoc) {
        this.initializeEditor(this.pendingDoc)
        this.pendingDoc = null
      }
      return
    }
    if (!this.dependencyStart) this.dependencyStart = Date.now()
    if (!this.dependencyWarned && Date.now() - this.dependencyStart > 5000) {
      console.warn("[collaboration] CodeMirror/ot not loaded yet; waiting to initialize.")
      this.dependencyWarned = true
    }
    if (!this.dependencyTimer) {
      this.dependencyTimer = setTimeout(() => {
        this.dependencyTimer = null
        this.waitForDependencies()
      }, 50)
    }
  }

  initializeEditor(data) {
    if (!this.editor) {
      this.editor = CodeMirror.fromTextArea(this.textareaTarget, { lineNumbers: true })
    }

    if (this.editorAdapter && this.editorAdapter.detach) {
      this.editorAdapter.detach()
    }
    this.editorAdapter = null
    this.editorClient = null

    this.editor.setValue(data.str || "")

    const serverAdapter = this.adapter
    const editorAdapter = new ot.CodeMirrorAdapter(this.editor)
    this.editorAdapter = editorAdapter
    this.editorClient = new ot.EditorClient(
      data.revision,
      data.clients || {},
      serverAdapter,
      editorAdapter
    )
  }

  requestResync() {
    if (this.subscription) {
      this.subscription.perform("resync")
    }
  }
}
