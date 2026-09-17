// Rhino ignores the `placeholder` attribute on <rhino-editor> and shows its own
// "Write something…". Pass the attribute to its placeholder extension instead.
// Call before the editor is built (before startEditor, or on rhino-before-initialize).
export function applyPlaceholder(editor) {
  const placeholder = editor.getAttribute("placeholder")
  if (!placeholder) return

  editor.starterKitOptions = {
    ...editor.starterKitOptions,
    rhinoPlaceholder: { placeholder }
  }
}
