import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { text: String }

  connect() {
    if (this.hasLabelTarget) {
      this.originalLabel = this.labelTarget.textContent.trim()
    }
  }

  async copy() {
    const url = this.textValue
    if (!url) return

    if (await this.tryNativeShare(url)) return

    const copied = await this.copyToClipboard(url)
    if (copied) {
      this.showCopied()
      return
    }

    window.prompt("Copy this link:", url)
  }

  async tryNativeShare(url) {
    if (!navigator.share) return false

    try {
      if (navigator.canShare && !navigator.canShare({ url })) return false
      await navigator.share({ url })
      return true
    } catch (error) {
      if (error?.name === "AbortError") return true
      return false
    }
  }

  async copyToClipboard(url) {
    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(url)
        return true
      } catch (error) {
        console.warn("Clipboard API failed, falling back.", error)
      }
    }

    return this.copyWithExecCommand(url)
  }

  copyWithExecCommand(url) {
    const textarea = document.createElement("textarea")
    textarea.value = url
    textarea.setAttribute("readonly", "")
    textarea.style.position = "absolute"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    const success = document.execCommand("copy")
    document.body.removeChild(textarea)
    return success
  }

  showCopied() {
    if (!this.hasLabelTarget) return

    this.labelTarget.textContent = "Copied"
    clearTimeout(this.resetTimeout)
    this.resetTimeout = setTimeout(() => {
      this.labelTarget.textContent = this.originalLabel || "Share"
    }, 1500)
  }
}
