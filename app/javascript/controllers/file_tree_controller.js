import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { roomSlug: String }
  static targets = ["list"]

  connect() {
    this.load()
  }

  async load() {
    const response = await fetch(`/rooms/${this.roomSlugValue}/files`)
    if (!response.ok) return
    const data = await response.json()
    this.listTarget.innerHTML = ""
    this.labels = new Map()
    this.activeLabel = null
    this.renderNodes(data.tree || [], this.listTarget)
    if (!this.selectedPath) {
      const firstFile = this.findFirstFile(data.tree || [])
      if (firstFile) this.selectFile(firstFile)
    }
  }

  renderNodes(nodes, container) {
    nodes.forEach((node) => {
      const item = document.createElement("div")
      item.className = `file-node ${node.type}`

      const label = document.createElement("button")
      label.type = "button"
      label.textContent = node.name
      label.className = "file-label"
      if (node.type === "file") {
        label.dataset.path = node.path
        this.labels.set(node.path, label)
        label.addEventListener("click", () => this.selectFile(node.path))
      }

      item.appendChild(label)
      container.appendChild(item)

      if (node.type === "dir" && node.children) {
        const children = document.createElement("div")
        children.className = "file-children"
        item.appendChild(children)
        this.renderNodes(node.children, children)
      }
    })
  }

  selectFile(path) {
    this.selectedPath = path
    if (this.activeLabel) this.activeLabel.classList.remove("is-active")
    const nextLabel = this.labels && this.labels.get(path)
    if (nextLabel) {
      nextLabel.classList.add("is-active")
      this.activeLabel = nextLabel
    }
    document.body.dataset.selectedRoom = this.roomSlugValue
    document.body.dataset.selectedPath = path
    document.dispatchEvent(
      new CustomEvent("file-selected", {
        detail: { path },
      })
    )
  }

  findFirstFile(nodes) {
    for (const node of nodes) {
      if (node.type === "file") return node.path
      if (node.type === "dir" && node.children) {
        const nested = this.findFirstFile(node.children)
        if (nested) return nested
      }
    }
    return null
  }
}
