// Whether a refresh of the page would take something away from the person using it: a
// dialog or a menu is open, or the cursor is in a field. A morph refresh closes the first
// two and puts back what the server knows of the third.
export function pageInUse() {
  if (document.querySelector("dialog[open], [popover]:popover-open")) return true

  let field = document.activeElement
  while (field?.shadowRoot?.activeElement) field = field.shadowRoot.activeElement
  if (!field) return false

  return field.isContentEditable ||
    field.matches("textarea, select, input:not([type=checkbox], [type=radio], [type=button], [type=submit], [type=reset], [type=file])")
}
