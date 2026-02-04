import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name"]

  connect() {
    this.handleFileSelected = (event) => {
      const path = event.detail && event.detail.path
      if (!path || !this.hasNameTarget) return
      const parts = path.split("/")
      this.nameTarget.textContent = parts[parts.length - 1] || path
    }
    document.addEventListener("file-selected", this.handleFileSelected)
  }

  disconnect() {
    document.removeEventListener("file-selected", this.handleFileSelected)
  }
}
