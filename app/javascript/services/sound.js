// The app's sounds: a few short, quiet notes for the moments worth hearing (a message
// sent, one arriving, a todo ticked off, someone joining a call).
//
// Nothing is loaded. Every sound is made here with Web Audio out of one or two voices:
// a note (a sine that dies away like a struck bar, with a little of its octave on top),
// a glide (a note that slides from one pitch to another) and air (a breath of noise).
// All pitches are from one scale, D major pentatonic, so any two sounds that meet are
// in tune with each other. Each is over within a quarter of a second.
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

const B3 = 246.94, D4 = 293.66, A4 = 440, B4 = 493.88
const D5 = 587.33, Fs5 = 739.99, A5 = 880, B5 = 987.77, D6 = 1174.66

// A sound is its voices: [ kind, how ], each starting `at` seconds in and lasting `last`
export const SOUNDS = {
  // Going out rises, coming in falls
  send:    [ [ "glide", { from: D5, to: A5, last: 0.11, level: 0.07 } ] ],
  receive: [ [ "glide", { from: A5, to: D5, last: 0.16, level: 0.08, ring: true } ] ],
  // Something for you, somewhere you aren't looking
  notify:  [ [ "note", { pitch: Fs5, last: 0.16, level: 0.08 } ], [ "note", { pitch: B5, at: 0.08, last: 0.22, level: 0.09 } ] ],
  mail:    [ [ "note", { pitch: B4, last: 0.18, level: 0.09 } ], [ "note", { pitch: Fs5, at: 0.09, last: 0.24, level: 0.08 } ] ],
  sent:    [ [ "air", { from: 600, to: 3600, last: 0.2, level: 0.03 } ], [ "note", { pitch: A5, at: 0.12, last: 0.2, level: 0.06 } ] ],
  done:    [ [ "note", { pitch: D5, last: 0.1, level: 0.06 } ], [ "note", { pitch: A5, at: 0.05, last: 0.12, level: 0.07 } ], [ "note", { pitch: D6, at: 0.1, last: 0.18, level: 0.07 } ] ],
  drop:    [ [ "glide", { from: 330, to: 220, last: 0.08, level: 0.11 } ] ],
  tuck:    [ [ "glide", { from: A5, to: D5, last: 0.1, level: 0.05 } ], [ "air", { from: 2400, to: 900, last: 0.1, level: 0.02 } ] ],
  trash:   [ [ "air", { from: 2600, to: 400, last: 0.16, level: 0.035 } ], [ "glide", { from: D4, to: B3 * 0.75, last: 0.14, level: 0.08 } ] ],
  error:   [ [ "note", { pitch: B3, last: 0.1, level: 0.09, wave: "triangle" } ], [ "note", { pitch: B3, at: 0.12, last: 0.12, level: 0.09, wave: "triangle" } ] ],
  join:    [ [ "note", { pitch: A4, last: 0.16, level: 0.09, soft: true } ], [ "note", { pitch: D5, at: 0.1, last: 0.22, level: 0.09, soft: true } ] ],
  leave:   [ [ "note", { pitch: D5, last: 0.16, level: 0.08, soft: true } ], [ "note", { pitch: A4, at: 0.1, last: 0.22, level: 0.08, soft: true } ] ]
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
  // A struck bar: there at once, then dying away. `soft` comes in gently and has no octave.
  note(context, out, at, { pitch, last, level, soft = false, wave = "sine" }) {
    tone(context, out, at, { from: pitch, last, level, attack: soft ? 0.02 : 0.005, wave })
    if (!soft) tone(context, out, at, { from: pitch * 2, last: last * 0.45, level: level * 0.2, attack: 0.004 })
  },

  // A note that slides to another pitch in the first half of its time
  glide(context, out, at, { from, to, last, level, ring = false }) {
    tone(context, out, at, { from, to, last, level, attack: 0.006 })
    if (ring) tone(context, out, at, { from: from * 2, to: to * 2, last: last * 0.5, level: level * 0.15, attack: 0.004 })
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

function tone(context, out, at, { from, to, last, level, attack, wave = "sine" }) {
  const oscillator = context.createOscillator()
  const loud = context.createGain()

  oscillator.type = wave
  oscillator.frequency.setValueAtTime(from, at)
  if (to) oscillator.frequency.exponentialRampToValueAtTime(to, at + last * 0.5)
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
