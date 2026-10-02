// The keys that move tiles around in the workspace (workspace_controller.js). They go
// with Alt, and on a Mac with Control and Option: Option alone types letters there,
// and moves by word. A page inside a tile hands them on (tile_page_controller.js),
// so they work wherever the keyboard is.
//
// Those are taken on some machines (a window manager, a screen reader), so each
// browser can pick another pair to hold: the shortcuts dialog has the choice
// (workspaces/_shortcuts, workspace_keys_controller.js), a cookie keeps it, and the
// server writes the keys by the same cookie (ApplicationHelper#workspace_key).
const MAC = /Mac|iP/.test(navigator.platform)

const HELD = {
  "alt": (event) => event.altKey && !event.ctrlKey && !event.metaKey,
  "ctrl-alt": (event) => event.ctrlKey && event.altKey && !event.metaKey,
  "ctrl-meta": (event) => event.ctrlKey && event.metaKey && !event.altKey,
  "alt-meta": (event) => event.altKey && event.metaKey && !event.ctrlKey
}
// What this kind of keyboard can choose from; the first is what it has unasked
const CHOICES = MAC ? [ "ctrl-alt", "ctrl-meta", "alt-meta" ] : [ "alt", "ctrl-alt" ]

export function workspaceModifier() {
  const chosen = document.cookie.match(/(?:^|; )workspace_keys=([\w-]+)/)?.[1]
  return CHOICES.includes(chosen) ? chosen : CHOICES[0]
}

export function chooseWorkspaceModifier(modifier) {
  if (CHOICES.includes(modifier)) document.cookie = `workspace_keys=${modifier}; path=/; max-age=31536000; samesite=lax`
}

// A page names the keys in many places (the shortcuts dialog, tooltips, the menu's
// commands), written by the server with what they went with then: "⌃⌥W", "Alt+W".
// With another choice those are rewritten where they stand, so nothing is loaded
// again and nothing half-typed is lost. `chosen` is { value, before, after }: the
// choice, and how the keys began and begin now ("⌃⌥" to "⌃⌘", "Alt+" to "Ctrl+Alt+").
export function renameWorkspaceKeys({ value, before, after }) {
  if (!before || !after || before === after) return

  for (const key of document.querySelectorAll("kbd")) {
    if (key.textContent.startsWith(before)) key.textContent = after + key.textContent.slice(before.length)
  }
  for (const named of document.querySelectorAll("[title]")) {
    if (named.title.includes(`(${before}`)) named.title = named.title.replace(`(${before}`, `(${after}`)
  }
  for (const choice of document.querySelectorAll("[data-controller~='workspace-keys']")) choice.value = value
}

const COMMANDS = {
  ArrowLeft: "left", KeyH: "left",
  ArrowRight: "right", KeyL: "right",
  ArrowUp: "up", KeyK: "up",
  ArrowDown: "down", KeyJ: "down",
  KeyW: "close",
  KeyF: "zoom",
  Equal: "grow", NumpadAdd: "grow",
  Minus: "shrink", NumpadSubtract: "shrink",
  KeyM: "menu",
  KeyR: "reload"
}
// Plus and minus are not where the American keyboard has them everywhere
const BY_CHARACTER = { "+": "grow", "=": "grow", "-": "shrink", "_": "shrink" }

// { name: "left" | … | "desk", desk: 3, shift: true } for a key that is the workspace's
export function workspaceCommand(event) {
  // (AltGr is Control and Alt to the browser, and types characters)
  const held = HELD[workspaceModifier()](event) && !event.getModifierState?.("AltGraph")
  if (!held) return null

  const desk = event.code.match(/^Digit([1-9])$/)
  const name = desk ? "desk" : COMMANDS[event.code] || BY_CHARACTER[event.key]
  return name ? { name, desk: desk ? Number(desk[1]) : null, shift: event.shiftKey } : null
}

// Cmd+K or Ctrl+K: the launcher
export function isLauncherKey(event) {
  return event.code === "KeyK" && (MAC ? event.metaKey : event.ctrlKey) && !event.altKey && !event.shiftKey
}
