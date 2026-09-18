// Tells the tool's presence controller what this page has open, so everyone
// else in the same tool sees a ring on it. A context is a type and an id, like
// "card:12"; nothing, or null, means "just here, nothing open".
//
// The last one is kept here as well: a page that opens straight onto a card
// (a notification link, ?card=12) says so while the presence controller may
// still be connecting, and the controller reads it as it comes up.
let lastReported = { context: "", at: 0 }

export function reportPresence(context) {
  lastReported = { context: context || "", at: Date.now() }
  window.dispatchEvent(new CustomEvent("presence:context", { detail: { context: lastReported.context } }))
}

// What this page said it had open, if it said so just now. Older than that and
// it belongs to a page that has since been left.
export function recentlyReportedContext(withinMs = 5000) {
  return Date.now() - lastReported.at < withinMs ? lastReported.context : ""
}
