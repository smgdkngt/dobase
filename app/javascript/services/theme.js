// Puts a theme on <html>, or takes it off again. The server renders a page with its
// theme already on; this is for a theme that changes while a page is open.
// `theme` is what Theme.payload gives: { version, name, mode, style, chrome_color }.
const root = document.documentElement

export function themeVersion() {
  return root.dataset.themeVersion || "default"
}

export function applyTheme(theme) {
  if (!theme?.version || theme.version === themeVersion()) return

  for (const property of [...root.style]) {
    if (property.startsWith("--") || property === "color-scheme") root.style.removeProperty(property)
  }
  for (const declaration of (theme.style || "").split("; ")) {
    const at = declaration.indexOf(": ")
    if (at > 0) root.style.setProperty(declaration.slice(0, at), declaration.slice(at + 2))
  }

  setData("theme", theme.name)
  setData("themeMode", theme.mode)
  root.dataset.themeVersion = theme.version
  setChromeColor(theme.chrome_color)
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
