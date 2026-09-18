# The vendored editor bundle

`rhino-editor.js` is not the package from npm. It is one esbuild bundle of
rhino-editor together with the TipTap extensions Dobase adds, all sharing a
single copy of `@tiptap/core`. A separately pinned extension would pull in a
second copy, giving the editor two schemas, and the extension would quietly do
nothing.

What it holds today:

| Export | Package | Used by |
| --- | --- | --- |
| `TipTapEditor`, `AttachmentManager` | `rhino-editor` | every editor |
| `Mention` | `@tiptap/extension-mention` | chat, card and todo comments |
| `Collaboration`, `CollaborationCaret` | `@tiptap/extension-collaboration`, `-caret` | documents, where several people write at once |
| `Y`, `Awareness`, `applyAwarenessUpdate`, `encodeAwarenessUpdate`, `removeAwarenessStates` | `yjs`, `y-protocols` | `services/document_sync.js` |

## Rebuilding it

```bash
npm i rhino-editor@0.18.3 "@tiptap/extension-mention@^3" "@tiptap/suggestion@^3" \
      "@tiptap/extension-collaboration@^3" "@tiptap/extension-collaboration-caret@^3" \
      yjs y-protocols esbuild
```

`entry.js` re-exports everything in the table above:

```js
export { TipTapEditor, AttachmentManager } from "rhino-editor"
export { Mention } from "@tiptap/extension-mention"
export { Collaboration } from "@tiptap/extension-collaboration"
export { CollaborationCaret } from "@tiptap/extension-collaboration-caret"
export * as Y from "yjs"
export { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from "y-protocols/awareness"
```

```bash
npx esbuild entry.js --bundle --format=esm --minify --outfile=rhino-editor.js
```

Check the bundle's last `export{...}` still lists every name above before
copying it over, and run the browser tests for documents and chat.
