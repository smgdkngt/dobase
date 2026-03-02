import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._roomElement = this.element._roomElement || null
    this._toolPath = this.element._toolPath || ""
    this._active = this.element._active || false

    this._onBeforeRender = this._handleBeforeRender.bind(this)
    this._onRender = this._handleRender.bind(this)
    this._onBeforeMorphEl = this._handleBeforeMorphElement.bind(this)
    document.addEventListener("turbo:before-render", this._onBeforeRender)
    document.addEventListener("turbo:render", this._onRender)
    document.addEventListener("turbo:before-morph-element", this._onBeforeMorphEl)

    if (this._active) this._applySidebarIndicator()
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this._onBeforeRender)
    document.removeEventListener("turbo:render", this._onRender)
    document.removeEventListener("turbo:before-morph-element", this._onBeforeMorphEl)
  }

  // Called by room_controller on join
  activate(roomElement, toolPath) {
    if (this._active && this._roomElement && this._roomElement !== roomElement) {
      this._forceLeaveExisting()
    }

    this._roomElement = roomElement
    this._toolPath = toolPath
    this._active = true

    this.element._roomElement = roomElement
    this.element._toolPath = toolPath
    this.element._active = true

    this._applySidebarIndicator()
  }

  // Called by room_controller on leave
  deactivate() {
    this._active = false
    this._roomElement = null
    this._toolPath = ""

    this.element._active = false
    this.element._roomElement = null
    this.element._toolPath = ""

    this.element.hidden = true
    this._removeReturnBanner()
    this._removeSidebarIndicator()
  }

  get active() {
    return this._active
  }

  get roomElement() {
    return this._roomElement
  }

  // ── Drag support ────────────────────────────────────────────────────

  startDrag(event) {
    if (!this._roomElement) return
    event.preventDefault()

    this._dragging = true
    const rect = this._roomElement.getBoundingClientRect()
    this._dragOffsetX = event.clientX - rect.left
    this._dragOffsetY = event.clientY - rect.top

    this._onPointerMove = this._handlePointerMove.bind(this)
    this._onPointerUp = this._handlePointerUp.bind(this)
    document.addEventListener("pointermove", this._onPointerMove)
    document.addEventListener("pointerup", this._onPointerUp)
    this._roomElement.style.transition = "none"
  }

  _handlePointerMove(event) {
    if (!this._dragging || !this._roomElement) return

    const x = Math.max(0, Math.min(event.clientX - this._dragOffsetX, window.innerWidth - this._roomElement.offsetWidth))
    const y = Math.max(0, Math.min(event.clientY - this._dragOffsetY, window.innerHeight - this._roomElement.offsetHeight))

    this._roomElement.style.left = `${x}px`
    this._roomElement.style.top = `${y}px`
    this._roomElement.style.right = "auto"
    this._roomElement.style.bottom = "auto"
  }

  _handlePointerUp() {
    this._dragging = false
    document.removeEventListener("pointermove", this._onPointerMove)
    document.removeEventListener("pointerup", this._onPointerUp)
    if (this._roomElement) this._roomElement.style.transition = ""
  }

  // ── Private ──────────────────────────────────────────────────────────

  _handleBeforeMorphElement(event) {
    if (!this._active) return

    // Protect #persistent-room and all its descendants from being morphed away
    if (this.element.contains(event.target)) {
      event.preventDefault()
    }
  }

  _handleBeforeRender(event) {
    if (!this._active || !this._roomElement) return

    // Skip morph renders — the morph handler takes care of those
    if (event.detail.renderMethod === "morph") return

    const newBody = event.detail.newBody
    const placeholder = newBody.querySelector("[data-persistent-room-placeholder]")
    const newContainer = newBody.querySelector("#persistent-room")

    if (placeholder) {
      // Navigating BACK to the room page — restore full view
      this._roomElement.classList.remove("persistent-room-pip")
      this._resetPosition()
      placeholder.replaceWith(this._roomElement)
      this._removeReturnBanner()
      if (newContainer) newContainer.hidden = true
    } else if (newContainer) {
      // Navigating to or between non-room pages — put PiP in new body
      if (!this._roomElement.classList.contains("persistent-room-pip")) {
        this._roomElement.classList.add("persistent-room-pip")
      }

      const banner = this.element.querySelector("[data-return-banner]")
      if (banner) newContainer.appendChild(banner)
      newContainer.appendChild(this._roomElement)
      newContainer.hidden = false
      this._ensureReturnBanner(newContainer)

      // Transfer state so the new controller instance picks it up
      newContainer._roomElement = this._roomElement
      newContainer._toolPath = this._toolPath
      newContainer._active = true
    }
  }

  _handleRender() {
    if (this._active) this._applySidebarIndicator()
  }

  _ensureReturnBanner(container) {
    if (container.querySelector("[data-return-banner]")) return

    const banner = document.createElement("a")
    banner.href = this._toolPath
    banner.dataset.returnBanner = ""
    banner.className = "persistent-room-return-banner"
    banner.setAttribute("data-action", "pointerdown->persistent-room#startDrag")
    banner.innerHTML = `<span>Return to call</span><span class="persistent-room-drag-hint">Drag to move</span>`
    container.insertBefore(banner, container.firstChild)
  }

  _addReturnBanner() {
    this._ensureReturnBanner(this.element)
  }

  _removeReturnBanner() {
    this.element.querySelector("[data-return-banner]")?.remove()
  }

  _resetPosition() {
    if (!this._roomElement) return
    this._roomElement.style.left = ""
    this._roomElement.style.top = ""
    this._roomElement.style.right = ""
    this._roomElement.style.bottom = ""
  }

  _applySidebarIndicator() {
    if (!this._toolPath) return
    const link = document.querySelector(`a.sidebar-tool-item[href="${this._toolPath}"]`)
    if (link) link.dataset.inCall = "true"
  }

  _removeSidebarIndicator() {
    document.querySelectorAll("[data-in-call]").forEach(el => delete el.dataset.inCall)
  }

  _forceLeaveExisting() {
    if (!this._roomElement) return
    const roomCtrl = this.application.getControllerForElementAndIdentifier(
      this._roomElement, "room"
    )
    roomCtrl?.leave()
  }
}
