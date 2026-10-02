// Puts a theme on <html>, or takes it off again. The server renders a page with its
// theme already on; this is for a theme that changes while a page is open.
// `theme` is what Theme.payload gives: { version, name, mode, style, chrome_color }.
const root = document.documentElement

export function themeVersion() {
  return root.dataset.themeVersion || "default"
}

// The offline page (public/offline.html) can't ask the server what the theme is, so
// the browser keeps the few colours it needs.
export function rememberTheme() {
  try {
    if (!root.dataset.theme) return localStorage.removeItem("dobase:theme")

    const style = getComputedStyle(root)
    localStorage.setItem("dobase:theme", JSON.stringify({
      background: style.getPropertyValue("--color-background").trim(),
      text: style.getPropertyValue("--color-text-primary").trim(),
      muted: style.getPropertyValue("--color-text-tertiary").trim()
    }))
  } catch {
    // No storage (private browsing, a full disk): the offline page keeps its own colours
  }
}

export function applyTheme(theme) {
  if (!theme?.version || theme.version === themeVersion()) return
  // Set at once: the same theme arrives more than once (each notification
  // subscription hears of it), and only the first should do anything
  root.dataset.themeVersion = theme.version

  // The old colours fade into the new ones where the browser can do that
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (document.startViewTransition && !still && !document.hidden) {
    // A transition that is skipped (another one started, the tab went away) rejects
    // its promises; the colours are on either way
    const transition = document.startViewTransition(() => wear(theme))
    for (const settled of [ transition.ready, transition.finished, transition.updateCallbackDone ]) settled?.catch(() => {})
  } else {
    wear(theme)
  }
}

function wear(theme) {
  for (const property of [...root.style]) {
    if (property.startsWith("--") || property === "color-scheme") root.style.removeProperty(property)
  }
  for (const declaration of (theme.style || "").split("; ")) {
    const at = declaration.indexOf(": ")
    if (at > 0) root.style.setProperty(declaration.slice(0, at), declaration.slice(at + 2))
  }

  setData("theme", theme.name)
  setData("themeMode", theme.mode)
  setData("typeface", theme.typeface)
  setChromeColor(theme.chrome_color)
  rememberTheme()
  // A tile in the workspace is a page of its own; the workspace passes the theme on
  window.dispatchEvent(new CustomEvent("theme:change", { detail: theme }))
}

function setData(name, value) {
  if (value) root.dataset[name] = value
  else delete root.dataset[name]
}

// A themed <meta name="theme-color"> goes first, ahead of the light and dark ones
// the app's own look uses, so it wins while it is there.
function setChromeColor(color) {
  let meta = document.querySelector('meta[name="theme-color"][data-theme-chrome]')
  if (!color) return meta?.remove()

  if (!meta) {
    meta = document.createElement("meta")
    meta.name = "theme-color"
    meta.dataset.themeChrome = ""
    const first = document.querySelector('meta[name="theme-color"]')
    first ? first.before(meta) : document.head.append(meta)
  }
  meta.content = color
}
