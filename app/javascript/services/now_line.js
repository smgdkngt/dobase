// Where the calendar's line for now lies in a day: the minutes since midnight on the
// clock of the zone the page is drawn in (<meta name="time-zone">), which is the
// signed-in person's, not necessarily the computer's.

/**
 * @param {Date} date
 * @param {string | undefined} timeZone an IANA name; one the browser doesn't know is its own zone
 * @returns {number}
 */
export function minutesIntoDay(date, timeZone) {
  let format
  try {
    format = new Intl.DateTimeFormat("en-GB", { hour: "numeric", minute: "numeric", hourCycle: "h23", timeZone })
  } catch {
    format = new Intl.DateTimeFormat("en-GB", { hour: "numeric", minute: "numeric", hourCycle: "h23" })
  }
  const parts = Object.fromEntries(format.formatToParts(date).map(part => [part.type, part.value]))
  return (Number(parts.hour) % 24) * 60 + Number(parts.minute)
}

/**
 * @param {number} minutes since midnight
 * @returns {string} how far down the day, for `top`
 */
export function nowLineTop(minutes) {
  return `${(minutes / (24 * 60)) * 100}%`
}
