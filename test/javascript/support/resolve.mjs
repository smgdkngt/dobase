// The folders config/importmap.rb pins as a whole (pin_all_from)
const PINNED = [ "services", "controllers", "channels", "elements" ]
const scripts = new URL("../../../app/javascript/", import.meta.url)

/** @type {import("node:module").ResolveHook} */
export function resolve(specifier, context, nextResolve) {
  const [ folder ] = specifier.split("/")
  if (PINNED.includes(folder)) return nextResolve(new URL(`${specifier}.js`, scripts).href, context)

  return nextResolve(specifier, context)
}
