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

// A key typed in a field inside a shadow root (the editor's link box) reaches the document
// with the editor as its target, so the shortcut handlers there don't see a field and "c",
// "/" or "?" fire while typing an address. Such keys stop before the document; the field
// and the editor around it have had them by then. Combinations with Cmd/Ctrl pass.
document.documentElement.addEventListener("keydown", (event) => {
  if (event.metaKey || event.ctrlKey) return

  const origin = event.composedPath()[0]
  if (origin === event.target || !(origin instanceof HTMLElement)) return
  if (origin.matches("input, textarea, select") || origin.isContentEditable) event.stopPropagation()
})

// Links with data-turbo-method are submitted through a form Turbo generates, which
// copies data-turbo-confirm but not data-turbo-confirm-button. Remember the link that
// was clicked, so its button label can be used when that form asks for confirmation.
let clickedConfirmLink = null
document.addEventListener("click", (event) => {
  clickedConfirmLink = event.target.closest?.("a[data-turbo-confirm]") ?? null
}, true)

function confirmButtonLabel(element, submitter) {
  const link = element instanceof HTMLFormElement && submitsLink(element, clickedConfirmLink) ? clickedConfirmLink : null
  return submitter?.dataset.turboConfirmButton || element?.dataset.turboConfirmButton || link?.dataset.turboConfirmButton || "Confirm"
}

// Turbo moves the link's query string into hidden fields, so the form's action has none
function submitsLink(form, link) {
  if (!link) return false
  const url = new URL(link.href)
  url.search = ""
  return url.href === form.action
}

// Custom confirmation dialog (replaces browser confirm())
Turbo.config.forms.confirm = (message, element, submitter) => {
  const dialog = document.getElementById("turbo-confirm-dialog")
  if (!dialog) return Promise.resolve(confirm(message))

  dialog.querySelector("#turbo-confirm-message").textContent = message

  const confirmBtn = dialog.querySelector("button[value='confirm']")
  confirmBtn.textContent = confirmButtonLabel(element, submitter)

  // Cancel, Escape and clicking outside close the dialog without setting a return value,
  // and the dialog survives morph refreshes, so clear what an earlier Confirm left behind
  dialog.returnValue = ""
  dialog.showModal()

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => {
      resolve(dialog.returnValue === "confirm")
    }, { once: true })
  })
}

// Mark an installed app window, so app_window.css can make it feel like a native app.
// Remembered for the window, in case it stops matching standalone in full screen.
const appWindow = window.matchMedia("(display-mode: standalone), (display-mode: window-controls-overlay)")

function markAppWindow() {
  try {
    if (appWindow.matches) sessionStorage.setItem("app-window", "1")
    if (sessionStorage.getItem("app-window")) document.documentElement.dataset.appWindow = ""
  } catch {
    if (appWindow.matches) document.documentElement.dataset.appWindow = ""
  }
}

markAppWindow()
document.addEventListener("turbo:load", markAppWindow)

// A page that is a tile in the workspace (workspace_controller.js) is in a frame with
// this name. The server draws it without the sidebar (ApplicationController#tile?):
// the browser says it is a frame when it loads one, and for every page after that
// Turbo says so here. Tiles are small and many, so everything in one is drawn a size
// smaller (workspace.css, <html data-in-tile>).
if (window.self !== window.top && (window.name === "workspace-tile" || window.name === "workspace-float")) {
  const root = document.documentElement
  let serverKnows = root.hasAttribute("data-in-tile")
  root.setAttribute("data-in-tile", "")
  // A frame over all the tiles that shows nothing but a dialog of this page (services/float.js)
  if (window.name === "workspace-float") root.setAttribute("data-floating", "")

  document.addEventListener("turbo:before-fetch-request", (event) => {
    event.detail.fetchOptions.headers["X-Tile"] = "1"
  })

  document.addEventListener("turbo:load", () => {
    if (document.querySelector("[data-controller~='tile-page']")) return

    if (serverKnows) {
      // Not a tool's page (signed out: the sign-in page). The workspace deals with it.
      window.parent.postMessage({ tile: "gone" }, window.location.origin)
    } else {
      // The browser didn't say it was loading a frame (plain HTTP, or a service worker
      // from before there were tiles fetched the page itself): ask again, now that
      // Turbo says so
      serverKnows = true
      Turbo.visit(window.location.href, { action: "replace" })
    }
  })
}

// Register service worker for PWA support
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}
