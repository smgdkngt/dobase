// Whether a key is being typed into something that has its own use for it: in a
// field the arrows move the caret, in a select or a group of radio buttons the
// choice, in a player the place in the film.
export function typing(event) {
  const target = event.composedPath()[0] || event.target
  if (!(target instanceof HTMLElement)) return false
  if (target.isContentEditable || target.matches("textarea, select, video, audio, [role='slider'], [role='tab'], [role='menuitem'], [role='option']")) return true

  return target.matches("input") && ![ "checkbox", "button", "submit" ].includes(target.type)
}
