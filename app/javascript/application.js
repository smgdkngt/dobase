// Configure your import map in config/importmap.rb
import "@hotwired/turbo-rails"
import "controllers"

// Track Turbo navigation state for system test reliability
document.addEventListener("turbo:load", () => {
  document.documentElement.removeAttribute("data-turbo-not-loaded")
  document.documentElement.removeAttribute("data-turbo-loading")
})

document.addEventListener("turbo:submit-start", (event) => {
  if (!event.target.closest("turbo-frame")) {
    document.documentElement.setAttribute("data-turbo-loading", "1")
  }
})

document.addEventListener("turbo:submit-end", (event) => {
  if (!event.detail.fetchResponse?.redirected) {
    document.documentElement.removeAttribute("data-turbo-loading")
  }
})

// Rich text editor (Rhino Editor — TipTap-based, ActionText compatible)
import "rhino-editor"

// Close open dialogs and popovers before Turbo morphs them
// (morph preserves top-layer state, so they'd stay stuck open)
document.addEventListener("turbo:before-morph-element", (event) => {
  if (event.target instanceof HTMLDialogElement && event.target.open) {
    event.target.close()
  }
  if (event.target.popover && event.target.matches(":popover-open")) {
    event.target.hidePopover()
  }
})

// Links with data-turbo-method are submitted through a form Turbo generates, which
// copies data-turbo-confirm but not data-turbo-confirm-button. Remember the link that
// was clicked, so its button label can be used when that form asks for confirmation.
let clickedConfirmLink = null
document.addEventListener("click", (event) => {
  clickedConfirmLink = event.target.closest?.("a[data-turbo-confirm]") ?? null
}, true)

function confirmButtonLabel(element, submitter) {
  const link = element instanceof HTMLFormElement && clickedConfirmLink?.href === element.action ? clickedConfirmLink : null
  return submitter?.dataset.turboConfirmButton || element?.dataset.turboConfirmButton || link?.dataset.turboConfirmButton || "Confirm"
}

// Custom confirmation dialog (replaces browser confirm())
Turbo.config.forms.confirm = (message, element, submitter) => {
  const dialog = document.getElementById("turbo-confirm-dialog")
  if (!dialog) return Promise.resolve(confirm(message))

  dialog.querySelector("#turbo-confirm-message").textContent = message

  const confirmBtn = dialog.querySelector("button[value='confirm']")
  confirmBtn.textContent = confirmButtonLabel(element, submitter)

  dialog.showModal()

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => {
      resolve(dialog.returnValue === "confirm")
    }, { once: true })
  })
}

// Register service worker for PWA support
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}
