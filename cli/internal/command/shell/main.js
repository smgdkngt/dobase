// Dobase as an app of its own: the server's pages in windows of this app, and
// every other address handed to the system. `dobase app install` puts this
// beside an Electron, with a config.json that names the server.
const { app, BrowserWindow, Menu, clipboard, desktopCapturer, dialog, nativeTheme, screen, session, shell, systemPreferences } = require("electron")
const fs = require("node:fs")
const path = require("node:path")
const { inside, page, outward } = require("./links")

const config = JSON.parse(fs.readFileSync(path.join(__dirname, "config.json"), "utf8"))
const mac = process.platform === "darwin"
const ours = (address) => inside(config.server, address)

app.setName(config.name)
// The sign-in lives where `dobase app remove` finds it
app.setPath("userData", config.data)
if (process.platform === "linux") app.setDesktopName("dobase.desktop")

// What the pages may ask for. The camera and the microphone are for calls.
const allowed = new Set(["notifications", "media", "display-capture", "fullscreen", "clipboard-read", "clipboard-sanitized-write", "speaker-selection"])
const kept = path.join(config.data, "window.json")
let started = false
let waiting = null // a link that came before the app could show it
let latest = null // the window last worked in

if (app.requestSingleInstanceLock()) {
  waiting = linkIn(process.argv)
  // A Mac hands a link over as an event, the others start the app once more with it
  app.on("open-url", (event, link) => {
    event.preventDefault()
    show(link)
  })
  app.on("second-instance", (event, argv) => show(linkIn(argv)))
  app.on("window-all-closed", () => app.quit())
  app.whenReady().then(start)
} else {
  app.quit()
}

function start() {
  started = true
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(mac ? [{ role: "appMenu" }] : []), { role: "fileMenu" }, { role: "editMenu" }, { role: "viewMenu" }, { role: "windowMenu" },
  ]))

  const pages = session.defaultSession
  pages.setPermissionCheckHandler((contents, permission, origin) => allowed.has(permission) && ours(origin))
  pages.setPermissionRequestHandler(async (contents, permission, answer, details) => {
    if (!allowed.has(permission) || !ours(details.requestingUrl)) return answer(false)
    // macOS asks about the camera and the microphone itself, once
    if (mac && permission === "media") {
      for (const kind of details.mediaTypes || []) await systemPreferences.askForMediaAccess(kind === "video" ? "camera" : "microphone")
    }
    answer(true)
  })
  // Sharing a screen: the system's own picker where there is one (macOS, and
  // Wayland, where asking for the sources is what shows it)
  pages.setDisplayMediaRequestHandler((request, answer) => {
    desktopCapturer.getSources({ types: ["screen", "window"] }).then((sources) => answer(sources.length ? { video: sources[0] } : null), () => answer(null))
  }, { useSystemPicker: true })
  // A link to a file opens a window that never gets a page: it goes with the file
  pages.on("will-download", (event, item, contents) => {
    const window = contents && BrowserWindow.fromWebContents(contents)
    if (window && !contents.getURL()) item.once("done", () => window.isDestroyed() || window.close())
  })

  open(page(config.server, waiting))
}

// show is the app being asked for: on a page, or just to come forward.
function show(link) {
  if (!started) {
    waiting = link || waiting
    return
  }
  const address = page(config.server, link)
  if (address || !latest) return open(address)
  if (latest.isMinimized()) latest.restore()
  latest.focus()
}

function linkIn(argv) {
  return argv.slice(1).find((argument) => page(config.server, argument)) || null
}

function open(address) {
  const window = new BrowserWindow({
    ...place(), minWidth: 360, minHeight: 400, title: config.name,
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#1c1c1e" : "#f5f5f7",
    webPreferences: { preload: path.join(__dirname, "preload.js"), spellcheck: true },
  })
  // The menu's keys work without its bar, which Alt would otherwise bring out
  window.setMenuBarVisibility(false)
  latest = window
  window.on("focus", () => { latest = window })
  window.on("close", () => {
    try {
      fs.writeFileSync(kept, JSON.stringify(window.getNormalBounds()))
    } catch {}
  })
  window.on("closed", () => {
    if (latest === window) latest = BrowserWindow.getAllWindows()[0] || null
  })

  const contents = window.webContents
  // Another page of the server gets a window of its own, the rest goes to the system
  contents.setWindowOpenHandler(({ url }) => {
    if (ours(url)) open(url)
    else if (outward(url)) shell.openExternal(url)
    return { action: "deny" }
  })
  const stay = (event) => {
    if (!event.isMainFrame || ours(event.url)) return
    event.preventDefault()
    if (outward(event.url)) shell.openExternal(event.url)
    if (!contents.getURL()) window.close()
  }
  contents.on("will-navigate", stay)
  contents.on("will-redirect", stay)
  // A page with unfinished work (an unsent mail, a call) is asked about first
  contents.on("will-prevent-unload", (event) => {
    const leave = dialog.showMessageBoxSync(window, {
      type: "question", buttons: ["Leave", "Stay"], defaultId: 1, cancelId: 1,
      message: "Leave this page?", detail: "Changes you made may not be saved.",
    }) === 0
    if (leave) event.preventDefault()
  })
  contents.on("context-menu", (event, at) => {
    const items = menuFor(contents, at)
    if (items.length) Menu.buildFromTemplate(items).popup({ window })
  })
  contents.on("did-fail-load", async (event, code, description, failed, mainFrame) => {
    // -3 is a page that gave way to another one, or to a download
    if (!mainFrame || code === -3 || window.isDestroyed()) return
    const { response } = await dialog.showMessageBox(window, {
      type: "warning", buttons: ["Try Again", "Close"], defaultId: 0, cancelId: 1,
      message: `${config.name} can't be reached`, detail: `${failed}\n${description}`,
    })
    if (window.isDestroyed()) return
    if (response === 0) contents.loadURL(failed)
    else window.close()
  })

  window.loadURL(address || config.server.replace(/\/*$/, "/"))
  return window
}

// place is where a new window goes: a step from the one you are in, or where
// the last one was when the app closed.
function place() {
  const from = BrowserWindow.getFocusedWindow() || latest
  if (from && !from.isDestroyed()) {
    const { x, y, width, height } = from.getNormalBounds()
    return { x: x + 28, y: y + 28, width, height }
  }
  try {
    const last = JSON.parse(fs.readFileSync(kept, "utf8"))
    const display = screen.getDisplayMatching(last).workArea
    // A screen that is gone takes its place along
    const inSight = last.x < display.x + display.width && last.x + last.width > display.x &&
      last.y < display.y + display.height && last.y + last.height > display.y
    if (last.width > 0 && last.height > 0 && inSight) return { x: last.x, y: last.y, width: last.width, height: last.height }
  } catch {}
  return { width: 1440, height: 900 }
}

// menuFor is the menu under the right mouse button, which a browser brings and
// Electron leaves out: spelling, the clipboard, and what to do with a link or
// a picture.
function menuFor(contents, at) {
  const items = []
  for (const word of at.dictionarySuggestions) items.push({ label: word, click: () => contents.replaceMisspelling(word) })
  if (at.misspelledWord) {
    items.push({ label: "Add to Dictionary", click: () => contents.session.addWordToSpellCheckerDictionary(at.misspelledWord) }, { type: "separator" })
  }
  if (at.linkURL) {
    if (ours(at.linkURL)) items.push({ label: "Open in New Window", click: () => open(at.linkURL) })
    else if (outward(at.linkURL)) items.push({ label: "Open in Browser", click: () => shell.openExternal(at.linkURL) })
    items.push({ label: "Copy Link", click: () => clipboard.writeText(at.linkURL) }, { type: "separator" })
  }
  if (at.mediaType === "image") {
    items.push({ label: "Copy Image", click: () => contents.copyImageAt(at.x, at.y) })
    if (at.srcURL) items.push({ label: "Save Image As…", click: () => contents.downloadURL(at.srcURL) })
    items.push({ type: "separator" })
  }
  if (at.isEditable) items.push({ role: "cut" }, { role: "copy" }, { role: "paste" }, { role: "selectAll" })
  else if (at.selectionText) items.push({ role: "copy" })
  while (items.length && items[items.length - 1].type === "separator") items.pop()
  return items
}
