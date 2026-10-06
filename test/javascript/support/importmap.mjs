// The app's scripts name each other the way the browser's import map does
// (config/importmap.rb): "services/tool_frame", not a path. This gives Node the same
// names, so a test imports a script exactly as the app does.
//
//   node --import ./test/javascript/support/importmap.mjs --test test/javascript/*.test.mjs
import { register } from "node:module"

register("./resolve.mjs", import.meta.url)

// What a script may ask of the page it is on, before any test sets more
globalThis.location ??= /** @type {any} */ (new URL("https://dobase.test/"))
