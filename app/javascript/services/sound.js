// The app's sounds: a few short, quiet taps for the moments worth hearing (a message
// sent, one arriving, a todo ticked off, someone joining a call).
//
// Nothing is loaded. Every sound is made here with Web Audio out of one or two voices:
// a knock (a low note struck and gone, like wood), a tap (a soft thump that slides),
// a click, air (a breath of noise) and, for calls, a round note. They are low and
// dry on purpose: closer to a key being pressed than to a chime. The pitched ones
// share one scale, so two sounds that meet are in tune. Each is over within a quarter
// of a second.
//
// Anything that should be heard says so in one of two ways:
//   - in a view: `data-sound="send"` on a form plays when the form went through, and on
//     anything else when it is clicked (application.js calls `listen`);
//   - from a controller: `play("receive", { once: "message-12" })`. `once` is a name
//     for what happened: with the app open in several tabs, only one of them plays it.
//
// Whether sounds play is a choice per browser (Profile, Notifications), on by default.

const KEY = "dobase:sounds"
const VOLUME = 1.4
// Long enough for another tab to have heard of the same thing, and to skip it
const ONCE_FOR_MS = 1500
// Left alone this long, the sound output is given back (a browser keeps it open otherwise)
const REST_AFTER_MS = 4000

const A3 = 220, D4 = 293.66, Fs4 = 369.99, A4 = 440

// A sound is its voices: [ kind, how ], each starting `at` seconds in and lasting `last`
export const SOUNDS = {
  // Going out rises, coming in falls
  send:    [ [ "click", { level: 0.03 } ], [ "tap", { from: 250, to: 380, last: 0.07, level: 0.11 } ] ],
  receive: [ [ "click", { level: 0.025 } ], [ "tap", { from: 380, to: 250, last: 0.09, level: 0.11 } ] ],
  // Something for you, somewhere you aren't looking: two knocks going up. Mail does the same from lower, with a wider step.
  notify:  [ [ "knock", { pitch: D4, last: 0.1, level: 0.11 } ], [ "knock", { pitch: Fs4, at: 0.09, last: 0.12, level: 0.11 } ] ],
  mail:    [ [ "knock", { pitch: A3, last: 0.09, level: 0.11 } ], [ "knock", { pitch: Fs4, at: 0.11, last: 0.13, level: 0.1 } ] ],
  sent:    [ [ "air", { from: 400, to: 2400, last: 0.22, level: 0.22 } ] ],
  done:    [ [ "knock", { pitch: D4, last: 0.06, level: 0.09 } ], [ "knock", { pitch: A4, at: 0.055, last: 0.1, level: 0.1 } ] ],
  drop:    [ [ "click", { level: 0.05 } ], [ "knock", { pitch: A3, last: 0.08, level: 0.115 } ] ],
  tuck:    [ [ "air", { from: 1400, to: 600, last: 0.11, level: 0.2 } ], [ "click", { at: 0.09, level: 0.035 } ] ],
  trash:   [ [ "air", { from: 2000, to: 300, last: 0.15, level: 0.12 } ], [ "tap", { from: 170, to: 100, at: 0.07, last: 0.1, level: 0.13 } ] ],
  error:   [ [ "tap", { from: 200, to: 130, last: 0.12, level: 0.12, wave: "triangle" } ], [ "tap", { from: 180, to: 120, at: 0.13, last: 0.13, level: 0.12, wave: "triangle" } ] ],
  join:    [ [ "note", { pitch: A3, last: 0.16, level: 0.11 } ], [ "note", { pitch: D4, at: 0.1, last: 0.2, level: 0.11 } ] ],
  leave:   [ [ "note", { pitch: D4, last: 0.16, level: 0.1 } ], [ "note", { pitch: A3, at: 0.1, last: 0.2, level: 0.1 } ] ]
}

export function soundsOn() {
  try {
    return localStorage.getItem(KEY) !== "off"
  } catch {
    return true
  }
}

export function setSounds(on) {
  try {
    on ? localStorage.removeItem(KEY) : localStorage.setItem(KEY, "off")
  } catch {
    // No storage (private window): they stay on for this page
  }
}

// Plays `name`. Nothing when sounds are off, when the browser hasn't let this page make
// sound yet (it does from the first click or key on), or when another tab took `once`.
// `always` is for trying a sound out where the choice is made.
export function play(name, { once, always = false } = {}) {
  if (!SOUNDS[name] || !(always || soundsOn())) return

  const context = output()
  if (!context) return

  if (once && navigator.locks) {
    navigator.locks.request(`dobase-sound-${once}`, { ifAvailable: true }, (lock) => {
      if (!lock) return

      sound(context, name)
      return new Promise((resolve) => setTimeout(resolve, ONCE_FOR_MS))
    })
  } else {
    sound(context, name)
  }
}

// The voices of `name` on any context, starting at `at`. `play` uses it on the page's
// own output; drawn on an OfflineAudioContext it gives the sound as numbers, to look at.
export function voice(context, out, name, at = context.currentTime) {
  let ends = at

  SOUNDS[name].forEach(([ kind, how ]) => {
    const from = at + (how.at || 0)
    VOICES[kind](context, out, from, how)
    ends = Math.max(ends, from + how.last)
  })

  return ends
}

// A form with data-sound plays when it went through; anything else with it when clicked.
// And the first click or key lets the page make sound at all.
export function listen() {
  document.addEventListener("turbo:submit-end", (event) => {
    const name = event.target.dataset?.sound
    if (name && event.detail.success) play(name)
  })

  document.addEventListener("click", (event) => {
    const marked = event.target.closest?.("[data-sound]")
    if (marked && !(marked instanceof HTMLFormElement)) play(marked.dataset.sound)
  })

  const wake = () => { if (missed && soundsOn()) output() }
  document.addEventListener("pointerdown", wake, { capture: true, passive: true })
  document.addEventListener("keydown", wake, { capture: true, passive: true })
}

let context = null
let master = null
let resting = null
// A sound asked for while the page wasn't allowed to make any: the next click or key
// opens the output, so the one after it is heard
let missed = false

function sound(context, name) {
  const ends = voice(context, master, name, context.currentTime + 0.01)

  document.dispatchEvent(new CustomEvent("sound:played", { detail: { name } }))
  clearTimeout(resting)
  resting = setTimeout(() => context.suspend(), (ends - context.currentTime) * 1000 + REST_AFTER_MS)
}

// The page's sound output, running. Null when it can't be had yet.
function output() {
  if (!context) {
    const Output = window.AudioContext || window.webkitAudioContext
    // Made before anyone touched the page it would never start, and the browser says so in the console
    if (!Output || (navigator.userActivation && !navigator.userActivation.hasBeenActive)) {
      missed = true
      return null
    }

    context = new Output({ latencyHint: "interactive" })
    // Everything goes through one filter that takes the edge off, and one volume
    const soften = context.createBiquadFilter()
    soften.type = "lowpass"
    soften.frequency.value = 6500
    master = context.createGain()
    master.gain.value = VOLUME
    master.connect(soften).connect(context.destination)
  }

  if (context.state !== "running") {
    // Asked for now, it runs by the time the sound starts a moment later. Where it
    // doesn't (the page wasn't touched yet), that sound is lost and the next touch wakes it.
    context.resume().then(() => { missed = false }, () => {})
    missed = context.state !== "running"
  }

  return context
}

const VOICES = {
  // A knock on wood: a click, then a low note that is there at once and gone at once,
  // with a little of the bar's own overtone at the start
  knock(context, out, at, { pitch, last, level }) {
    VOICES.click(context, out, at, { level: level * 0.25 })
    tone(context, out, at, { from: pitch * 1.12, to: pitch, bend: 0.02, last, level, attack: 0.003 })
    tone(context, out, at, { from: pitch * 3.9, last: last * 0.3, level: level * 0.12, attack: 0.002 })
  },

  // A soft thump that slides from one low pitch to another
  tap(context, out, at, { from, to, last, level, wave = "sine" }) {
    tone(context, out, at, { from, to, bend: last * 0.6, last, level, attack: 0.003, wave })
  },

  // A round, quiet note that comes in gently: for people arriving and leaving
  note(context, out, at, { pitch, last, level }) {
    tone(context, out, at, { from: pitch, last, level, attack: 0.015 })
  },

  // The tick at the front of a knock or a tap: a few thousandths of a second of noise
  click(context, out, at, { level, last = 0.008 }) {
    const source = context.createBufferSource()
    const band = context.createBiquadFilter()
    const loud = context.createGain()

    source.buffer = noise(context)
    band.type = "bandpass"
    band.frequency.value = 2200
    band.Q.value = 0.9
    loud.gain.setValueAtTime(level, at)
    loud.gain.exponentialRampToValueAtTime(0.0001, at + last)

    source.connect(band).connect(loud).connect(out)
    source.start(at)
    source.stop(at + last + 0.01)
  },

  // Noise through a narrow band that moves: a breath, upward or downward
  air(context, out, at, { from, to, last, level }) {
    const source = context.createBufferSource()
    const band = context.createBiquadFilter()
    const loud = context.createGain()

    source.buffer = noise(context)
    band.type = "bandpass"
    band.Q.value = 1.3
    band.frequency.setValueAtTime(from, at)
    band.frequency.exponentialRampToValueAtTime(to, at + last)
    loud.gain.setValueAtTime(0.0001, at)
    loud.gain.linearRampToValueAtTime(level, at + last * 0.35)
    loud.gain.exponentialRampToValueAtTime(0.0001, at + last)

    source.connect(band).connect(loud).connect(out)
    source.start(at)
    source.stop(at + last + 0.02)
  }
}

function tone(context, out, at, { from, to, bend, last, level, attack, wave = "sine" }) {
  const oscillator = context.createOscillator()
  const loud = context.createGain()

  oscillator.type = wave
  oscillator.frequency.setValueAtTime(from, at)
  if (to) oscillator.frequency.exponentialRampToValueAtTime(to, at + bend)
  loud.gain.setValueAtTime(0.0001, at)
  loud.gain.linearRampToValueAtTime(level, at + attack)
  loud.gain.exponentialRampToValueAtTime(0.0001, at + last)

  oscillator.connect(loud).connect(out)
  oscillator.start(at)
  oscillator.stop(at + last + 0.02)
}

const noises = new WeakMap()

// Half a second of noise, made once for a context
function noise(context) {
  if (!noises.has(context)) {
    const buffer = context.createBuffer(1, context.sampleRate / 2, context.sampleRate)
    const samples = buffer.getChannelData(0)
    for (let index = 0; index < samples.length; index++) samples[index] = Math.random() * 2 - 1
    noises.set(context, buffer)
  }

  return noises.get(context)
}
