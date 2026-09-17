// Client-side toast, for messages triggered by a JS fetch rather than a full
// page load (where the server-rendered shared/_flash partial handles it).
// Mirrors that partial's markup/classes so it looks and behaves the same —
// including being picked up by the existing "flash" Stimulus controller
// already connected to #flash (dismiss button, click-outside-free auto-remove).
const ICONS = {
  alert: '<circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/>',
  notice: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'
}

const CLOSE_ICON = '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'

function svg(paths, size) {
  const xmlns = "http://www.w3.org/2000/svg"
  const icon = document.createElementNS(xmlns, "svg")
  icon.setAttribute("width", size)
  icon.setAttribute("height", size)
  icon.setAttribute("viewBox", "0 0 24 24")
  icon.setAttribute("fill", "none")
  icon.setAttribute("stroke", "currentColor")
  icon.setAttribute("stroke-width", "2")
  icon.setAttribute("stroke-linecap", "round")
  icon.setAttribute("stroke-linejoin", "round")
  icon.setAttribute("class", "shrink-0")
  icon.setAttribute("aria-hidden", "true")
  icon.innerHTML = paths
  return icon
}

// type: "alert" (default) or "notice"
export function showFlash(message, type = "alert") {
  const container = document.getElementById("flash")
  if (!container) return

  const el = document.createElement("div")
  el.className = `flash flash-${type}`
  el.setAttribute("role", "alert")
  el.dataset.flashTarget = "message"
  el.dataset.action = "click->flash#dismiss"

  const text = document.createElement("span")
  text.className = "flex-1"
  text.textContent = message

  const dismiss = document.createElement("button")
  dismiss.type = "button"
  dismiss.className = "ml-2 opacity-70 hover:opacity-100"
  dismiss.dataset.action = "click->flash#dismiss"
  dismiss.appendChild(svg(CLOSE_ICON, 16))

  el.append(svg(ICONS[type] || ICONS.alert, 18), text, dismiss)
  container.appendChild(el)
  setTimeout(() => el.remove(), 5000)
}
