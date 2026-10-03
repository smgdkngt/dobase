// Puts a theme on <html>, or takes it off again. The server renders a page with its
// theme already on; this is for a theme that changes while a page is open.
// `theme` is what Theme.payload gives: { version, name, mode, style, chrome_color }.
import { api } from "services/api"

const root = document.documentElement
const dark = window.matchMedia("(prefers-color-scheme: dark)")

// Whether the system is light or dark right now
export function scheme() {
  return dark.matches ? "dark" : "light"
}

// Someone can have one theme for light and one for dark. Only the browser knows
// which of the two it is, so it keeps the server told (a cookie the next page is
// drawn by), and asks for the other theme when the system changes over.
function tellScheme() {
  document.cookie = `scheme=${scheme()}; path=/; max-age=31536000; samesite=lax`
}

function schemeChanged() {
  tellScheme()
  if (root.dataset.themeFollowsSystem) refreshTheme()
}

// The theme this page should be in, asked of the server again
export async function refreshTheme() {
  const theme = await api("/appearance")
  if (theme) applyTheme(theme)
}

if (document.cookie.match(/(?:^|; )scheme=(\w+)/)?.[1] !== scheme()) schemeChanged()
dark.addEventListener("change", schemeChanged)

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

// `fade: false` is for a tile in the workspace: the page around it fades the whole
// window, tiles included, and a fade of the tile's own would come in after that one.
export function applyTheme(theme, { fade = true } = {}) {
  if (!theme?.version) return
  // Said even when the colours stay as they are: whether the system going light or
  // dark brings another theme
  setData("themeFollowsSystem", theme.follows_system ? "true" : null)
  if (theme.version === themeVersion()) return
  // Set at once: the same theme arrives more than once (each notification
  // subscription hears of it), and only the first should do anything
  root.dataset.themeVersion = theme.version

  // The old colours fade into the new ones where the browser can do that
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (!fade) {
    wearAtOnce(theme)
  } else if (document.startViewTransition && !still && !document.hidden) {
    // A transition that is skipped (another one started, the tab went away) rejects
    // its promises; the colours are on either way
    const transition = document.startViewTransition(() => wear(theme))
    for (const settled of [ transition.ready, transition.finished, transition.updateCallbackDone ]) settled?.catch(() => {})
  } else {
    wear(theme)
  }
}

// Every colour at the same moment: nothing eases into the new theme by itself (a
// button's own fade would trail behind everything around it)
function wearAtOnce(theme) {
  root.dataset.themeChanging = ""
  wear(theme)
  // The browser works the new colours out here, while nothing may ease; after that
  // there is nothing left to ease into
  void root.offsetWidth
  delete root.dataset.themeChanging
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
