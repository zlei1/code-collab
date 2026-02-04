import { Controller } from "@hotwired/stimulus"
import { getConsumer } from "lib/cable_consumer"
import { cableConnected, cableDisconnected, createCableToken } from "lib/cable_status"

export default class extends Controller {
  static values = { roomId: Number, userLabel: String }
  static targets = ["grid", "status", "toggleButton", "disconnectOverlay"]

  connect() {
    this.consumer = getConsumer()
    this.cableStatusToken = createCableToken("video")
    this.subscription = this.consumer.subscriptions.create(
      { channel: "RoomSignalChannel", room_id: this.roomIdValue },
      {
        received: (data) => this.received(data),
        connected: () => cableConnected(this.cableStatusToken),
        disconnected: () => cableDisconnected(this.cableStatusToken),
      }
    )
    this.handleCableDisconnected = () => this.clearPresence()
    window.addEventListener("cable:disconnected", this.handleCableDisconnected)
    this.handleCableDisconnectedUi = () => this.setDisconnected(true)
    this.handleCableConnectedUi = () => this.setDisconnected(false)
    window.addEventListener("cable:disconnected", this.handleCableDisconnectedUi)
    window.addEventListener("cable:connected", this.handleCableConnectedUi)
    this.peers = new Map()
    this.presence = new Map()
    this.clientId = null
    this.joined = false
    this.presenceJoined = false
    this.pendingSignals = []
    this.pendingPresence = null
    this.statusTimer = null
    this.draggingTile = null
    this.localLabel = this.hasUserLabelValue ? this.userLabelValue : "You"
    this.isDisconnected = false
    this.dragHandlers = {
      dragstart: (event) => this.handleDragStart(event),
      dragover: (event) => this.handleDragOver(event),
      drop: (event) => this.handleDrop(event),
      dragend: (event) => this.handleDragEnd(event),
    }
    this.bindDragHandlers()
    this.updateToggleButton()
  }

  disconnect() {
    this.stop()
    if (this.subscription) this.consumer.subscriptions.remove(this.subscription)
    this.subscription = null
    cableConnected(this.cableStatusToken)
    this.pendingSignals = []
    this.unbindDragHandlers()
    window.removeEventListener("cable:disconnected", this.handleCableDisconnected)
    window.removeEventListener("cable:disconnected", this.handleCableDisconnectedUi)
    window.removeEventListener("cable:connected", this.handleCableConnectedUi)
  }

  async start() {
    if (this.joined) return
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.setStatus("Your browser does not support camera/microphone access.")
      return
    }
    try {
      this.setStatus("")
      this.joined = true
      this.updateToggleButton()
      this.ensureTile("local", this.localLabel, true)

      this.localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      this.addVideo("local", this.localStream, true)
      this.attachLocalTracksToPeers()
      this.sendSignal({ type: "media", has_media: true })
    } catch (error) {
      console.error("Failed to start video", error)
      this.joined = false
      this.updateToggleButton()
      this.setTileMediaState("local", false)

      if (error.name === "NotFoundError") {
        this.setStatus("No camera or microphone found. Please connect a device and try again.")
      } else if (error.name === "NotAllowedError") {
        this.setStatus("Permission denied. Please allow camera/microphone access.")
      } else {
        this.setStatus("Failed to start video.")
      }
    }
  }

  stop() {
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop())
      this.localStream = null
    }
    if (this.presenceJoined) {
      this.sendSignal({ type: "media", has_media: false })
      this.sendSignal({ type: "leave" })
    }
    this.presenceJoined = false
    this.peers.forEach((peer) => peer.connection.close())
    this.peers.clear()
    this.joined = false
    this.clearVideo("local")
    this.setTileMediaState("local", false)
    this.setStatus("")
    this.updateToggleButton()
  }

  received(data) {
    if (data.type === "welcome") {
      this.clientId = data.client_id
      if (this.pendingSignals.length > 0) {
        const queued = [...this.pendingSignals]
        this.pendingSignals = []
        queued.forEach((payload) => this.received(payload))
      }
      if (this.pendingPresence) {
        const presence = this.pendingPresence
        this.pendingPresence = null
        this.applyPresence(presence)
      }
      if (!this.presenceJoined) {
        this.sendSignal({ type: "join", has_media: Boolean(this.localStream) })
        this.presenceJoined = true
      }
      return
    }
    if (data.type === "presence") {
      if (!this.clientId) {
        this.pendingPresence = data
        return
      }
      this.applyPresence(data)
      return
    }
    if (data.type !== "signal" || data.sender_id === this.clientId) return

    const payload = data.payload
    if (!payload) return
    if (!this.clientId && payload.target) {
      this.pendingSignals.push(data)
      return
    }
    if (payload.target && payload.target !== this.clientId) return

    if (payload.type === "join") {
      this.ensurePeer(data.sender_id)
      if (this.joined && this.localStream) this.maybeOffer(data.sender_id)
      if (this.presenceJoined) {
        this.sendSignal({
          type: "presence",
          target: data.sender_id,
          has_media: Boolean(this.localStream),
        })
      }
      return
    }

    if (payload.type === "leave") {
      this.removePeerConnection(data.sender_id)
      this.setTileMediaState(data.sender_id, false)
      return
    }

    if (payload.type === "media") {
      this.ensurePeer(data.sender_id)
      if (this.joined) this.maybeOffer(data.sender_id)
      return
    }

    if (payload.type === "presence") {
      this.ensurePeer(data.sender_id)
      if (this.joined && this.localStream) this.maybeOffer(data.sender_id)
      return
    }

    if (payload.type === "offer") {
      this.handleOffer(data.sender_id, payload)
      return
    }

    if (payload.type === "answer") {
      this.handleAnswer(data.sender_id, payload)
      return
    }

    if (payload.type === "ice") {
      this.handleIce(data.sender_id, payload)
    }
  }

  async handleOffer(peerId, payload) {
    const peer = this.ensurePeer(peerId)
    const connection = peer.connection
    const offerCollision = peer.makingOffer || connection.signalingState !== "stable"
    peer.ignoreOffer = !peer.polite && offerCollision
    if (peer.ignoreOffer) return

    await connection.setRemoteDescription({ type: "offer", sdp: payload.sdp })
    if (this.localStream) this.addLocalTracks(peer)
    const answer = await connection.createAnswer()
    await connection.setLocalDescription(answer)
    this.sendSignal({ type: "answer", sdp: answer.sdp, target: peerId })
  }

  async handleAnswer(peerId, payload) {
    const peer = this.ensurePeer(peerId)
    await peer.connection.setRemoteDescription({ type: "answer", sdp: payload.sdp })
  }

  async handleIce(peerId, payload) {
    const peer = this.ensurePeer(peerId)
    if (peer.ignoreOffer) return
    if (payload.candidate) {
      await peer.connection.addIceCandidate(payload.candidate)
    }
  }

  ensurePeer(peerId) {
    if (this.peers.has(peerId)) return this.peers.get(peerId)

    const connection = new RTCPeerConnection({
      iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
    })

    const peer = {
      connection,
      tracksAdded: false,
      makingOffer: false,
      ignoreOffer: false,
      polite: this.clientId ? this.clientId < peerId : true,
    }

    connection.onicecandidate = (event) => {
      if (event.candidate) {
        this.sendSignal({ type: "ice", candidate: event.candidate, target: peerId })
      }
    }

    connection.onnegotiationneeded = async () => {
      await this.makeOffer(peerId)
    }

    connection.ontrack = (event) => {
      this.addVideo(peerId, event.streams[0])
    }

    connection.onconnectionstatechange = () => {
      if (["disconnected", "failed", "closed"].includes(connection.connectionState)) {
        this.removePeerConnection(peerId)
        this.setTileMediaState(peerId, false)
      }
    }

    if (this.localStream) {
      this.addLocalTracks(peer)
    }
    this.peers.set(peerId, peer)
    return peer
  }

  addVideo(id, stream, muted = false) {
    const tileId = this.tileIdFor(id)
    const label = this.labelForPeer(id)
    const email = this.emailForPeer(id)
    this.ensureTile(tileId, label, tileId === "local", email)
    let video = this.gridTarget.querySelector(`video[data-peer='${tileId}']`)
    if (!video) {
      video = document.createElement("video")
      video.dataset.peer = tileId
      video.autoplay = true
      video.playsInline = true
      video.muted = muted
      video.setAttribute("draggable", "false")
      const frame = this.gridTarget.querySelector(`.video-tile[data-peer='${tileId}'] .video-frame`)
      if (frame) frame.appendChild(video)
    }
    video.srcObject = stream
    const placeholder = this.gridTarget.querySelector(`.video-tile[data-peer='${tileId}'] .video-placeholder`)
    if (placeholder) placeholder.classList.add("hidden")
    this.setTileMediaState(tileId, true)
  }

  sendSignal(payload) {
    if (!this.subscription) return
    this.subscription.perform("signal", { payload })
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
  }

  notify(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    clearTimeout(this.statusTimer)
    this.statusTimer = setTimeout(() => {
      this.statusTarget.textContent = ""
    }, 3000)
  }

  applyPresence(data) {
    const clients = Array.isArray(data.clients) ? data.clients : []
    const seen = new Set()
    const visibleClientIds = this.selectVisibleClients(clients)

    clients.forEach((entry) => {
      if (!entry || !entry.client_id) return
      const clientId = entry.client_id
      this.presence.set(clientId, entry)
      const tileId = this.tileIdFor(clientId)
      if (visibleClientIds.has(clientId)) {
        const email = entry.email || ""
        const label = this.displayName(entry, email)
        this.ensureTile(tileId, label, tileId === "local", email)
        this.setTileInfo(tileId, label, email)
        const hasMedia = clientId === this.clientId && this.localStream ? true : Boolean(entry.has_media)
        this.setTileMediaState(tileId, hasMedia)
      } else {
        this.removeTile(tileId)
      }
      seen.add(clientId)
    })

    Array.from(this.presence.keys()).forEach((clientId) => {
      if (seen.has(clientId)) return
      this.presence.delete(clientId)
      if (clientId === this.clientId) {
        const tileId = this.tileIdFor(clientId)
        this.removeTile(tileId)
      } else {
        this.removePeer(clientId)
      }
    })
  }

  selectVisibleClients(clients) {
    const groups = new Map()
    clients.forEach((entry) => {
      if (!entry || !entry.client_id) return
      const key = entry.user_id ? `user:${entry.user_id}` : `client:${entry.client_id}`
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push(entry)
    })

    const visible = new Set()
    groups.forEach((entries) => {
      let chosen = entries.find((entry) => entry.client_id === this.clientId)
      if (!chosen) chosen = entries.find((entry) => entry.has_media)
      if (!chosen) chosen = entries[0]
      if (chosen) visible.add(chosen.client_id)
    })
    return visible
  }

  clearPresence() {
    const localTileId = this.tileIdFor(this.clientId)
    this.peers.forEach((_peer, clientId) => {
      this.removePeer(clientId)
    })
    this.peers.clear()
    this.presence.clear()
    this.pendingSignals = []
    this.pendingPresence = null
    this.presenceJoined = false
    this.clientId = null

    const tiles = Array.from(this.gridTarget.querySelectorAll(".video-tile"))
    tiles.forEach((tile) => {
      if (localTileId && tile.dataset.peer === localTileId) return
      tile.remove()
    })

    if (this.localStream && localTileId) {
      const label = this.parseName(this.localLabel)
      const email = this.parseEmail(this.localLabel)
      this.ensureTile(localTileId, label, true, email)
      this.setTileMediaState(localTileId, true)
    }
  }

  ensureTile(peerId, label, isLocal = false, email = "") {
    let tile = this.gridTarget.querySelector(`.video-tile[data-peer='${peerId}']`)
    if (tile) {
      this.setTileInfo(peerId, label, email)
      return tile
    }

    tile = document.createElement("div")
    tile.className = "video-tile"
    tile.dataset.peer = peerId
    tile.setAttribute("draggable", "true")

    const info = document.createElement("div")
    info.className = "video-info"

    const dot = document.createElement("span")
    dot.className = "video-presence-dot"

    const text = document.createElement("div")
    text.className = "video-text"

    const nameNode = document.createElement("div")
    nameNode.className = "video-name"
    nameNode.textContent = label

    const emailNode = document.createElement("div")
    emailNode.className = "video-email"
    emailNode.textContent = email

    text.appendChild(nameNode)
    text.appendChild(emailNode)
    info.appendChild(dot)
    info.appendChild(text)

    const media = document.createElement("div")
    media.className = "video-media"

    const frame = document.createElement("div")
    frame.className = "video-frame"

    const placeholder = document.createElement("div")
    placeholder.className = "video-placeholder"
    placeholder.textContent = "Camera on"

    if (isLocal) {
      placeholder.classList.add("local")
    }

    frame.appendChild(placeholder)
    media.appendChild(frame)

    tile.appendChild(info)
    tile.appendChild(media)
    this.gridTarget.appendChild(tile)
    return tile
  }

  setTileInfo(peerId, label, email = "") {
    const tile = this.gridTarget.querySelector(`.video-tile[data-peer='${peerId}']`)
    if (!tile) return
    const nameNode = tile.querySelector(".video-name")
    if (nameNode) nameNode.textContent = label
    const emailNode = tile.querySelector(".video-email")
    if (emailNode) emailNode.textContent = email
  }

  setTileMediaState(peerId, hasMedia) {
    const tileId = this.tileIdFor(peerId)
    const tile = this.gridTarget.querySelector(`.video-tile[data-peer='${tileId}']`)
    if (!tile) return
    tile.classList.toggle("has-media", Boolean(hasMedia))
    const dot = tile.querySelector(".video-presence-dot")
    if (dot) dot.classList.toggle("is-media", Boolean(hasMedia))
    if (!hasMedia) this.clearVideo(tileId)
  }

  clearVideo(peerId) {
    const tileId = this.tileIdFor(peerId)
    const tile = this.gridTarget.querySelector(`.video-tile[data-peer='${tileId}']`)
    if (!tile) return
    const video = tile.querySelector("video")
    if (video) video.remove()
    const placeholder = tile.querySelector(".video-placeholder")
    if (placeholder) placeholder.classList.remove("hidden")
  }

  tileIdFor(peerId) {
    if (peerId === "local") return "local"
    if (peerId === this.clientId) return "local"
    return peerId
  }

  labelForPeer(peerId) {
    if (peerId === "local" || peerId === this.clientId) return this.parseName(this.localLabel)
    const entry = this.presence.get(peerId)
    if (entry && entry.label) return entry.label
    if (entry && entry.email) return entry.email
    return "Online user"
  }

  emailForPeer(peerId) {
    if (peerId === "local" || peerId === this.clientId) {
      return this.parseEmail(this.localLabel)
    }
    const entry = this.presence.get(peerId)
    if (entry && entry.email) return entry.email
    return ""
  }

  parseEmail(label) {
    if (!label) return ""
    const parts = String(label).split(" - ")
    if (parts.length > 1) return parts.slice(1).join(" - ").trim()
    if (label.includes("@")) return label.trim()
    return ""
  }

  parseName(label) {
    if (!label) return "Online user"
    const parts = String(label).split(" - ")
    return parts[0].trim()
  }

  displayName(entry, email) {
    const label = entry.label || entry.email || "Online user"
    if (email && label.includes(" - ")) {
      const parts = String(label).split(" - ")
      if (parts.length > 1 && parts.slice(1).join(" - ").trim() === email) {
        return parts[0].trim()
      }
    }
    return label
  }

  removePeerConnection(peerId) {
    const peer = this.peers.get(peerId)
    if (peer) peer.connection.close()
    this.peers.delete(peerId)
  }

  removePeer(peerId) {
    this.removePeerConnection(peerId)
    const tileId = this.tileIdFor(peerId)
    const tile = this.gridTarget.querySelector(`.video-tile[data-peer='${tileId}']`)
    if (tile) tile.remove()
  }

  removeTile(peerId) {
    const tile = this.gridTarget.querySelector(`.video-tile[data-peer='${peerId}']`)
    if (tile) tile.remove()
  }

  addLocalTracks(peer) {
    if (!this.localStream || peer.tracksAdded) return
    this.localStream.getTracks().forEach((track) => peer.connection.addTrack(track, this.localStream))
    peer.tracksAdded = true
  }

  attachLocalTracksToPeers() {
    this.peers.forEach((peer, peerId) => {
      this.addLocalTracks(peer)
      this.maybeOffer(peerId)
    })
  }

  maybeOffer(peerId) {
    const peer = this.ensurePeer(peerId)
    peer.polite = this.clientId ? this.clientId < peerId : peer.polite
    if (peer.connection.signalingState === "stable" && this.localStream) {
      this.makeOffer(peerId)
    }
  }

  async makeOffer(peerId) {
    const peer = this.ensurePeer(peerId)
    const connection = peer.connection
    if (!this.joined || !this.localStream) return
    if (peer.makingOffer) return
    try {
      peer.makingOffer = true
      const offer = await connection.createOffer()
      if (connection.signalingState !== "stable") return
      await connection.setLocalDescription(offer)
      this.sendSignal({ type: "offer", sdp: offer.sdp, target: peerId })
    } catch (error) {
      console.error("Negotiation failed", error)
    } finally {
      peer.makingOffer = false
    }
  }

  toggle() {
    if (this.isDisconnected) return
    if (this.joined) {
      this.stop()
    } else {
      this.start()
    }
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return
    this.toggleButtonTarget.textContent = this.joined ? "Disconnect" : "Join video"
    this.toggleButtonTarget.disabled = this.isDisconnected
  }

  setDisconnected(state) {
    this.isDisconnected = state
    if (this.hasDisconnectOverlayTarget) {
      this.disconnectOverlayTarget.classList.toggle("is-visible", state)
    }
    if (this.hasStatusTarget) {
      if (state) {
        this.statusTarget.textContent = "掉线中"
      } else if (this.statusTarget.textContent === "掉线中") {
        this.statusTarget.textContent = ""
      }
    }
    this.updateToggleButton()
  }

  bindDragHandlers() {
    if (!this.hasGridTarget) return
    this.gridTarget.addEventListener("dragstart", this.dragHandlers.dragstart)
    this.gridTarget.addEventListener("dragover", this.dragHandlers.dragover)
    this.gridTarget.addEventListener("drop", this.dragHandlers.drop)
    this.gridTarget.addEventListener("dragend", this.dragHandlers.dragend)
  }

  unbindDragHandlers() {
    if (!this.hasGridTarget) return
    this.gridTarget.removeEventListener("dragstart", this.dragHandlers.dragstart)
    this.gridTarget.removeEventListener("dragover", this.dragHandlers.dragover)
    this.gridTarget.removeEventListener("drop", this.dragHandlers.drop)
    this.gridTarget.removeEventListener("dragend", this.dragHandlers.dragend)
  }

  handleDragStart(event) {
    const tile = event.target.closest(".video-tile")
    if (!tile) return
    this.draggingTile = tile
    tile.classList.add("dragging")
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", tile.dataset.peer || "")
    }
  }

  handleDragOver(event) {
    if (!this.draggingTile) return
    event.preventDefault()
    const tile = event.target.closest(".video-tile")
    if (!tile || tile === this.draggingTile) return
    const rect = tile.getBoundingClientRect()
    const insertAfter = event.clientY > rect.top + rect.height / 2
    if (insertAfter) {
      tile.after(this.draggingTile)
    } else {
      tile.before(this.draggingTile)
    }
  }

  handleDrop(event) {
    if (!this.draggingTile) return
    event.preventDefault()
  }

  handleDragEnd() {
    if (!this.draggingTile) return
    this.draggingTile.classList.remove("dragging")
    this.draggingTile = null
  }
}
