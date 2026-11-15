import { Controller } from "@hotwired/stimulus"

// Only the browser knows which time zone it is in. It says so to the server with a
// cookie (`browser_time_zone`, read by ApplicationController#suggested_time_zone),
// fills the sign-up form's field with it, and remembers when the offer to show
// times in that zone was waved away (shared/time_zone_notice).
export default class extends Controller {
  static targets = ["field", "notice"]

  connect() {
    const zone = browserTimeZone()
    if (zone && readCookie("browser_time_zone") !== zone) writeCookie("browser_time_zone", zone)
  }

  fieldTargetConnected(field) {
    const zone = browserTimeZone()
    if (zone) field.value = zone
  }

  // Not again for this zone, in this browser
  dismiss() {
    const zone = browserTimeZone()
    if (zone) writeCookie("time_zone_dismissed", zone)
    this.noticeTargets.forEach(notice => notice.remove())
  }
}

function browserTimeZone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null
  } catch {
    return null
  }
}

function readCookie(name) {
  const value = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`))?.[1]
  return value === undefined ? null : decodeURIComponent(value)
}

function writeCookie(name, value) {
  document.cookie = `${name}=${encodeURIComponent(value)}; path=/; max-age=31536000; samesite=lax`
}
