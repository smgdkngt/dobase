// Runs in each page before its own scripts. A browser tells a page it is an
// installed app through display-mode; here nothing does, so the page is told
// the way app_window.css reads it: html[data-app-window].
function mark() {
  if (!document.documentElement) return false
  document.documentElement.dataset.appWindow = ""
  return true
}

if (!mark()) {
  new MutationObserver((changes, observer) => {
    if (mark()) observer.disconnect()
  }).observe(document, { childList: true })
}
