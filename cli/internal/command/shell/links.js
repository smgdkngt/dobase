// Which addresses are the app's own, and what a link handed to the app means.

// inside says whether address is a page of the server.
function inside(server, address) {
  try {
    const home = new URL(server.replace(/\/*$/, "/"))
    const target = new URL(address)
    return target.origin === home.origin && (target.pathname + "/").startsWith(home.pathname)
  } catch {
    return false
  }
}

// page is the page of the server a link stands for: the link itself when it is
// one of the server's, or what web+dobase://tools/8/board names there. null for
// anything else, so nothing handed to the app takes it off its server.
function page(server, link) {
  if (typeof link !== "string") return null
  if (link.startsWith("web+dobase:")) link = server.replace(/\/*$/, "/") + link.replace(/^web\+dobase:\/*/, "")
  return inside(server, link) ? link : null
}

// outward says whether an address is one to hand to the system: a page for the
// browser, a letter for the mail program, a number to call.
function outward(address) {
  try {
    return ["http:", "https:", "mailto:", "tel:"].includes(new URL(address).protocol)
  } catch {
    return false
  }
}

module.exports = { inside, page, outward }
