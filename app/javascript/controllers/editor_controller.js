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
  static targets = [
    "textarea",
    "loader",
    "disconnectOverlay",
    "diffModal",
    "diffServer",
    "diffLocal",
    "diffMeta",
    "diffApply",
    "diffDiscard",
    "diffClose",
  ]
  static values = { roomId: Number, roomSlug: String }

  connect() {
    this.adapter = new ActionCableAdapter()
    this.consumer = getConsumer()
    this.cableStatusToken = createCableToken("editor")
    this.currentPath = null
    this.pendingDoc = null
    this.hasConnected = false
    this.dependencyTimer = null
    this.dependencyStart = null
    this.dependencyWarned = false
    this.isDisconnected = false
    this.offlineMode = false
    this.offlineKey = null
    this.lastServerDoc = null
    this.lastServerRevision = 0
    this.offlineChangeHandler = null
    this.handleDiffApply = () => this.applyOfflineChanges()
    this.handleDiffDiscard = () => this.discardOfflineChanges()

    this.handleFileSelected = (event) => this.openFile(event.detail.path)
    document.addEventListener("file-selected", this.handleFileSelected)
    this.handleCableDisconnected = () => this.setDisconnected(true)
    this.handleCableConnected = () => this.setDisconnected(false)
    window.addEventListener("cable:disconnected", this.handleCableDisconnected)
    window.addEventListener("cable:connected", this.handleCableConnected)

    const selectedRoom = document.body.dataset.selectedRoom
    const selectedPath = document.body.dataset.selectedPath
    if (selectedRoom === this.roomSlugValue && selectedPath) {
      this.openFile(selectedPath)
    }
  }

  disconnect() {
    document.removeEventListener("file-selected", this.handleFileSelected)
    if (this.subscription) this.consumer.subscriptions.remove(this.subscription)
    if (this.editorAdapter && this.editorAdapter.detach) this.editorAdapter.detach()
    if (this.editor && this.offlineChangeHandler) {
      this.editor.off("change", this.offlineChangeHandler)
    }
    this.subscription = null
    this.consumer = null
    cableConnected(this.cableStatusToken)
    if (this.dependencyTimer) clearTimeout(this.dependencyTimer)
    this.dependencyTimer = null
    window.removeEventListener("cable:disconnected", this.handleCableDisconnected)
    window.removeEventListener("cable:connected", this.handleCableConnected)
  }

  openFile(path) {
    if (!path || path === this.currentPath) return
    this.currentPath = path
    if (this.subscription) this.consumer.subscriptions.remove(this.subscription)
    if (this.editorAdapter && this.editorAdapter.detach) this.editorAdapter.detach()
    if (this.editor && this.offlineChangeHandler) {
      this.editor.off("change", this.offlineChangeHandler)
    }
    this.editorAdapter = null
    this.editorClient = null
    this.offlineKey = this.buildOfflineKey(path)

    this.subscription = this.consumer.subscriptions.create(
      { channel: "RoomCollabChannel", room_id: this.roomIdValue, path: path },
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
    this.hasConnected = false
    this.waitForDependencies()
  }

  received(data) {
    if (data.type === "resync") {
      if (data.client_id && data.client_id !== this.adapter.clientId) return
      this.requestResync()
      return
    }
    if (data.type === "doc") {
      this.adapter.setClientId(data.client_id)
      this.lastServerDoc = data.str || ""
      this.lastServerRevision = data.revision
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
      console.warn("[editor] CodeMirror/ot not loaded yet; waiting to initialize.")
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
    if (this.hasLoaderTarget) {
      this.loaderTarget.remove()
    }
    
    if (!this.editor) {
      this.editor = CodeMirror.fromTextArea(this.textareaTarget, { lineNumbers: true })
    }

    if (this.editorAdapter && this.editorAdapter.detach) {
      this.editorAdapter.detach()
    }
    this.editorAdapter = null
    this.editorClient = null

    this.editor.setValue(data.str || "")
    this.applyDisconnectedState()

    const serverAdapter = this.adapter
    const editorAdapter = new ot.CodeMirrorAdapter(this.editor)
    this.editorAdapter = editorAdapter
    this.editorClient = new ot.EditorClient(
      data.revision,
      data.clients || {},
      serverAdapter,
      editorAdapter
    )

    if (!this.offlineChangeHandler) {
      this.offlineChangeHandler = () => {
        if (this.offlineMode) {
          this.persistOfflineDoc()
        }
      }
    }
    this.editor.on("change", this.offlineChangeHandler)
    this.attachDiffHandlers()
    this.maybeShowOfflineDiff()
  }

  requestResync() {
    if (this.subscription) {
      this.subscription.perform("resync")
    }
  }

  setDisconnected(state) {
    this.isDisconnected = state
    if (this.hasDisconnectOverlayTarget) {
      this.disconnectOverlayTarget.classList.toggle("is-visible", state)
      this.disconnectOverlayTarget.classList.toggle("is-nonblocking", state)
    }
    this.offlineMode = state
    if (state) {
      this.persistOfflineDoc(true)
    }
    this.applyDisconnectedState()
  }

  applyDisconnectedState() {
    if (!this.editor) return
    this.editor.setOption("readOnly", false)
    if (this.hasDisconnectOverlayTarget) {
      this.disconnectOverlayTarget.innerHTML = this.isDisconnected
        ? '<div class="panel-overlay-text">Offline mode: changes will sync after reconnect.</div>'
        : ""
    }
  }

  buildOfflineKey(path) {
    return `offline-collab:${this.roomSlugValue}:${path}`
  }

  loadOfflineState() {
    if (!this.offlineKey) return null
    try {
      const raw = localStorage.getItem(this.offlineKey)
      if (!raw) return null
      return JSON.parse(raw)
    } catch (error) {
      console.warn("[editor] Failed to load offline state", error)
      return null
    }
  }

  persistOfflineDoc(force = false) {
    if (!this.offlineKey || !this.editor) return
    if (!force && !this.offlineMode) return
    try {
      const payload = {
        room: this.roomSlugValue,
        path: this.currentPath,
        localDoc: this.editor.getValue(),
        updatedAt: new Date().toISOString(),
        baseRevision: this.lastServerRevision,
      }
      localStorage.setItem(this.offlineKey, JSON.stringify(payload))
    } catch (error) {
      console.warn("[editor] Failed to persist offline state", error)
    }
  }

  clearOfflineState() {
    if (!this.offlineKey) return
    try {
      localStorage.removeItem(this.offlineKey)
    } catch (error) {
      console.warn("[editor] Failed to clear offline state", error)
    }
  }

  maybeShowOfflineDiff() {
    const offline = this.loadOfflineState()
    if (!offline || !offline.localDoc) return
    if (this.lastServerDoc === null) return
    if (offline.localDoc === this.lastServerDoc) {
      this.clearOfflineState()
      return
    }
    this.showDiffModal(this.lastServerDoc, offline.localDoc, offline.updatedAt)
  }

  attachDiffHandlers() {
    if (this.hasDiffApplyTarget) {
      this.diffApplyTarget.removeEventListener("click", this.handleDiffApply)
      this.diffApplyTarget.addEventListener("click", this.handleDiffApply)
    }
    const discardTargets = []
    if (this.hasDiffDiscardTarget) discardTargets.push(this.diffDiscardTarget)
    if (this.hasDiffCloseTarget) discardTargets.push(this.diffCloseTarget)
    discardTargets.forEach((target) => {
      target.removeEventListener("click", this.handleDiffDiscard)
      target.addEventListener("click", this.handleDiffDiscard)
    })
  }

  showDiffModal(serverDoc, localDoc, updatedAt) {
    if (!this.hasDiffModalTarget) return
    const span = this.computeDiffSpan(serverDoc, localDoc)
    if (this.hasDiffServerTarget) {
      this.diffServerTarget.innerHTML = this.renderDiff(serverDoc, span.start, span.endOld, "diff-server")
    }
    if (this.hasDiffLocalTarget) {
      this.diffLocalTarget.innerHTML = this.renderDiff(localDoc, span.start, span.endNew, "diff-local")
    }
    if (this.hasDiffMetaTarget) {
      const timeText = updatedAt ? new Date(updatedAt).toLocaleString() : "unknown"
      this.diffMetaTarget.textContent = `Offline edits captured at ${timeText}`
    }
    this.diffModalTarget.style.display = "flex"
    this.diffModalTarget.classList.remove("is-hidden")
  }

  closeDiffModal() {
    if (!this.hasDiffModalTarget) return
    this.diffModalTarget.style.display = "none"
    this.diffModalTarget.classList.add("is-hidden")
  }

  applyOfflineChanges() {
    const offline = this.loadOfflineState()
    if (!offline || !offline.localDoc || !this.editorClient) {
      this.closeDiffModal()
      return
    }
    const operation = this.buildSingleSpanOperation(this.lastServerDoc, offline.localDoc)
    if (operation && !operation.isNoop()) {
      this.editorClient.applyClient(operation)
    }
    this.clearOfflineState()
    this.closeDiffModal()
  }

  discardOfflineChanges() {
    this.clearOfflineState()
    this.closeDiffModal()
  }

  computeDiffSpan(oldText, newText) {
    const oldLen = oldText.length
    const newLen = newText.length
    let start = 0
    while (start < oldLen && start < newLen && oldText[start] === newText[start]) {
      start += 1
    }
    let endOld = oldLen - 1
    let endNew = newLen - 1
    while (endOld >= start && endNew >= start && oldText[endOld] === newText[endNew]) {
      endOld -= 1
      endNew -= 1
    }
    return { start, endOld, endNew }
  }

  buildSingleSpanOperation(oldText, newText) {
    const span = this.computeDiffSpan(oldText, newText)
    const start = span.start
    const endOld = span.endOld
    const endNew = span.endNew
    const oldMiddleLength = endOld >= start ? endOld - start + 1 : 0
    const newMiddle = endNew >= start ? newText.slice(start, endNew + 1) : ""
    const retainSuffix = oldText.length - (endOld + 1)
    const operation = new ot.TextOperation()
    if (start > 0) operation.retain(start)
    if (oldMiddleLength > 0) operation["delete"](oldMiddleLength)
    if (newMiddle.length > 0) operation.insert(newMiddle)
    if (retainSuffix > 0) operation.retain(retainSuffix)
    return operation
  }

  renderDiff(text, start, end, highlightClass) {
    const safe = (value) =>
      value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/\"/g, "&quot;")
        .replace(/'/g, "&#39;")
    const before = safe(text.slice(0, start))
    const hasMiddle = end >= start
    const middle = hasMiddle ? safe(text.slice(start, end + 1)) : ""
    const after = safe(text.slice(end + 1))
    const highlight = hasMiddle && middle.length > 0
      ? `<span class="diff-highlight ${highlightClass}">${middle}</span>`
      : ""
    return `${before}${highlight}${after}`
  }
}
