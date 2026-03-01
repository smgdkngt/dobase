// Configure your import map in config/importmap.rb
import "@hotwired/turbo-rails"
import "controllers"

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
