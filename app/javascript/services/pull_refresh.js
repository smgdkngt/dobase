// Pulled down from the top of a page, a page on a touch screen draws itself again, as
// a phone's own apps do. An app on the home screen has no reload button and no
// browser gesture for it: this is the one way to say "show me what is there now".
//
// What is pulled is told first (a cancelable "pull-to-refresh" event that bubbles):
// the mailbox asks its server for new mail instead, and says "pull-to-refresh:done"
// when it has its answer. Otherwise the page is drawn again where it is
// (services/tile.js#visitPage, a morph).

import { visitPage } from "services/tile"
import { pullsDown } from "services/sheet"

/** How far the indicator comes down, at most, in pixels */
export const FURTHEST = 80

/** How far it has to come before letting go refreshes */
export const REFRESHING_AT = 56

/**
 * How far the indicator follows a finger that has gone this far: half, and never
 * past FURTHEST, so a long pull feels like it meets resistance
 * @param {number} distance
 * @returns {number}
 */
export function shown(distance) {
  return Math.max(0, Math.min(FURTHEST, distance / 2))
}

/**
 * Whether letting go with the indicator this far down refreshes
 * @param {number} indicator
 * @returns {boolean}
 */
export function refreshes(indicator) {
  return indicator >= REFRESHING_AT
}

/**
 * @param {Document} document
 */
export function listen(document) {
  /** @type {{ target: Element, x: number, y: number, pulling: boolean, indicator: number } | null} */
  let pull = null
  /** @type {HTMLElement | null} */
  let spinner = null

  document.addEventListener("touchstart", (event) => {
    pull = null
    if (event.touches.length !== 1 || !matchMedia("(pointer: coarse)").matches) return
    const target = /** @type {Element} */ (event.target)
    if (!target.closest?.("main, .tile-page")) return
    if (target.closest("input, textarea, select, [contenteditable=true], rhino-editor, dialog, [popover]")) return
    if (document.querySelector("dialog[open], .sidebar.open, [data-swiping]")) return
    if (window.scrollY > 0 || scrolledDown(target)) return

    const touch = event.touches[0]
    pull = { target, x: touch.clientX, y: touch.clientY, pulling: false, indicator: 0 }
  }, { passive: true })

  document.addEventListener("touchmove", (event) => {
    if (!pull) return
    const touch = event.touches[0]
    const down = touch.clientY - pull.y
    if (!pull.pulling) {
      if (Math.abs(down) < 6 && Math.abs(touch.clientX - pull.x) < 6) return
      if (!pullsDown(down, touch.clientX - pull.x)) {
        pull = null
        return
      }
      pull.pulling = true
    }
    pull.indicator = shown(down)
    spinner ||= makeSpinner(document)
    spinner.hidden = false
    spinner.toggleAttribute("data-armed", refreshes(pull.indicator))
    spinner.style.transform = `translate(-50%, ${pull.indicator}px) rotate(${pull.indicator * 4}deg)`
    spinner.style.opacity = String(Math.min(1, pull.indicator / REFRESHING_AT))
  }, { passive: true })

  const letGo = (/** @type {TouchEvent} */ event) => {
    if (!pull?.pulling || !spinner) {
      pull = null
      return
    }
    const { target, indicator } = pull
    pull = null
    const indicatorShown = spinner
    if (event.type === "touchend" && refreshes(indicator)) {
      indicatorShown.setAttribute("data-refreshing", "")
      indicatorShown.style.transform = `translate(-50%, ${REFRESHING_AT}px)`
      const asked = target.dispatchEvent(new CustomEvent("pull-to-refresh", { bubbles: true, cancelable: true }))
      if (asked) visitPage(target)
      // Gone once the page is drawn again, or after a while if nothing came
      const done = () => hide(indicatorShown)
      document.addEventListener("turbo:render", done, { once: true })
      document.addEventListener("turbo:frame-render", done, { once: true })
      document.addEventListener("pull-to-refresh:done", done, { once: true })
      setTimeout(done, 4000)
    } else {
      hide(indicatorShown)
    }
  }
  document.addEventListener("touchend", letGo)
  document.addEventListener("touchcancel", letGo)
}

/**
 * Whether anything the finger is on has been scrolled down from its top
 * @param {Element} target
 * @returns {boolean}
 */
function scrolledDown(target) {
  for (let element = /** @type {Element | null} */ (target); element; element = element.parentElement) {
    if (element.scrollTop > 0) return true
  }
  return false
}

/**
 * @param {Document} document
 * @returns {HTMLElement}
 */
function makeSpinner(document) {
  const spinner = document.createElement("div")
  spinner.className = "pull-refresh"
  spinner.setAttribute("aria-hidden", "true")
  spinner.hidden = true
  document.body.append(spinner)
  // A visit brings a new body, without it
  document.addEventListener("turbo:before-render", (event) => {
    /** @type {any} */ (event).detail.newBody?.append(spinner)
  })
  return spinner
}

/**
 * @param {HTMLElement} spinner
 */
function hide(spinner) {
  spinner.removeAttribute("data-refreshing")
  spinner.removeAttribute("data-armed")
  spinner.style.transform = ""
  spinner.style.opacity = "0"
  setTimeout(() => { if (spinner.style.opacity === "0") spinner.hidden = true }, 200)
}
