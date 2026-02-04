import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "passwordInput", "linkInput", "passwordToggle"]
    static values = { url: String, roomSlug: String }

    connect() {
        this.boundClose = this.close.bind(this)
    }

    disconnect() {
    }

    open() {
        this.modalTarget.classList.remove("is-hidden")
        this.modalTarget.style.display = "flex"
        // Focus on copy button or something?
    }

    close() {
        this.modalTarget.classList.add("is-hidden")
        this.modalTarget.style.display = "none"
    }

    togglePassword() {
        const input = this.passwordInputTarget
        const isVisible = input.type === "text"
        input.type = isVisible ? "password" : "text"

        if (this.hasPasswordToggleTarget) {
            this.passwordToggleTarget.setAttribute("aria-pressed", String(!isVisible))
            this.passwordToggleTarget.setAttribute("aria-label", isVisible ? "Show password" : "Hide password")
        }
    }

    copy(event) {
        this.linkInputTarget.select()
        navigator.clipboard.writeText(this.linkInputTarget.value)

        const button = event.currentTarget
        const originalText = button.innerText
        button.innerText = "Copied!"
        setTimeout(() => {
            button.innerText = originalText
        }, 2000)
    }

}
