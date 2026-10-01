// The keys that move tiles around in the workspace (workspace_controller.js). They go
// with Alt, and on a Mac with Control and Option: Option alone types letters there,
// and moves by word. A page inside a tile hands them on (side_pane_page_controller.js),
// so they work wherever the keyboard is.
const MAC = /Mac|iP/.test(navigator.platform)

const COMMANDS = {
  ArrowLeft: "left", KeyH: "left",
  ArrowRight: "right", KeyL: "right",
  ArrowUp: "up", KeyK: "up",
  ArrowDown: "down", KeyJ: "down",
  KeyW: "close", KeyQ: "close",
  KeyF: "zoom",
  KeyM: "menu",
  Space: "launcher"
}

// { name: "left" | … | "desk", desk: 3, shift: true } for a key that is the workspace's
export function workspaceCommand(event) {
  const held = MAC
    ? event.ctrlKey && event.altKey && !event.metaKey
    : event.altKey && !event.ctrlKey && !event.metaKey && !event.getModifierState?.("AltGraph")
  if (!held) return null

  const desk = event.code.match(/^Digit([1-9])$/)
  const name = desk ? "desk" : COMMANDS[event.code]
  return name ? { name, desk: desk ? Number(desk[1]) : null, shift: event.shiftKey } : null
}

// Cmd+K or Ctrl+K: the launcher
export function isLauncherKey(event) {
  return event.code === "KeyK" && (MAC ? event.metaKey : event.ctrlKey) && !event.altKey && !event.shiftKey
}
