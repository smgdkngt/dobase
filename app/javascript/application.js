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

// The tool beside (shared/_side_pane, side_pane_controller.js) goes next to <body>, where
// Turbo's page swaps leave it alone. A page without the template has nobody signed in,
// or somebody else: the pane of whoever was here goes.
function installSidePane() {
  const template = document.getElementById("side-pane-template")
  const pane = document.getElementById("side-pane")
  const owner = template?.content.firstElementChild.dataset.sidePaneUserIdValue

  if (pane && pane.dataset.sidePaneUserIdValue !== owner) pane.remove()
  if (template && !document.getElementById("side-pane")) document.documentElement.append(template.content.cloneNode(true))
}

if (window.self === window.top) {
  document.addEventListener("turbo:load", installSidePane)
} else if (window.name === "side-pane") {
  // This page is the one beside. The server leaves the sidebar out of it
  // (ApplicationController#side_pane?): the browser says it is a frame when it loads
  // one, and for every page after that Turbo says so here.
  const root = document.documentElement
  let serverKnows = root.hasAttribute("data-in-side-pane")
  root.setAttribute("data-in-side-pane", "")

  document.addEventListener("turbo:before-fetch-request", (event) => {
    event.detail.fetchOptions.headers["X-Side-Pane"] = "1"
  })

  document.addEventListener("turbo:load", () => {
    if (document.querySelector("[data-controller~='side-pane-page']")) return

    if (serverKnows) {
      // Not a tool's page (signed out: the sign-in page). Nothing to keep beside.
      window.parent.postMessage({ sidePane: "gone" }, window.location.origin)
    } else {
      // The browser didn't say (a service worker from before there was a pane fetched
      // the page itself): ask again, now that Turbo does
      serverKnows = true
      Turbo.visit(window.location.href, { action: "replace" })
    }
  })
}

// Register service worker for PWA support
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}
