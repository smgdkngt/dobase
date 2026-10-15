// Hands a page to the installed app (app_links/show): the browser goes to the
// web+dobase:// link, which the app takes, and this tab stays behind with a way to
// go on here instead. A plain script in the <head>, as workspace_gate.js is.
//
//   data-link: the web+dobase:// link for the page
//   data-page: the page itself, for a window that is the app already
(() => {
  const script = document.currentScript
  if (!script) return

  const { link, page } = script.dataset
  // The app from `dobase app install` says so before any script runs (its
  // preload.js); a browser's installed app by its display mode, or by what
  // application.js remembered of it for the window
  let remembered = false
  try {
    remembered = Boolean(sessionStorage.getItem("app-window"))
  } catch {
    // No storage: the display mode alone
  }
  const inTheApp = remembered || document.documentElement.hasAttribute("data-app-window") ||
    window.matchMedia("(display-mode: standalone), (display-mode: window-controls-overlay)").matches

  if (inTheApp) return window.location.replace(page)
  // Once the page is drawn, so that what is left behind is this page
  document.addEventListener("DOMContentLoaded", () => { window.location.href = link })
})()
