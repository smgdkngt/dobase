// Says which element has the keyboard because of a key, for the styles to mark it.
//
// A browser draws its focus mark by :focus-visible: on what got the focus by the
// keyboard, not by a click. Safari doesn't count a focus that a script moved there,
// even when a key asked for it: the arrow keys (arrow_keys_controller.js) go from
// item to item and nothing shows where they are. So the page keeps track itself:
// after a key, whatever takes the focus is marked data-keyboard-focus until it loses
// it, and the styles treat that like :focus-visible (the `focus-visible` variant in
// application.css, and :is(:focus-visible, [data-keyboard-focus]) where a rule is
// written out).
let byKey = false

document.addEventListener("keydown", () => { byKey = true }, true)
document.addEventListener("pointerdown", () => { byKey = false }, true)
document.addEventListener("focusin", (event) => {
  if (byKey) event.target.setAttribute?.("data-keyboard-focus", "")
})
document.addEventListener("focusout", (event) => {
  event.target.removeAttribute?.("data-keyboard-focus")
})
