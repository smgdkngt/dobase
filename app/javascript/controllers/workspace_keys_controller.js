import { Controller } from "@hotwired/stimulus"
import { chooseWorkspaceModifier, renameWorkspaceKeys, workspaceModifier } from "services/workspace_keys"

// The choice of what the workspace's keys go with, in the shortcuts dialog
// (workspaces/_shortcuts). It counts from the next key on, on this page and in
// every tile (they all read the same cookie). The keys this page names are
// rewritten where they stand; the workspace and its tiles pass the word on so
// theirs are too (workspace_controller.js, tile_page_controller.js).
export default class extends Controller {
  choose() {
    const chosen = { value: this.element.value, before: this.prefixOf(workspaceModifier()), after: this.prefixOf(this.element.value) }

    chooseWorkspaceModifier(chosen.value)
    renameWorkspaceKeys(chosen)
    window.dispatchEvent(new CustomEvent("workspace:keys-chosen", { detail: chosen }))
  }

  // How a key written with that choice begins: "Ctrl+Opt+", "Alt+"
  prefixOf(value) {
    return Array.from(this.element.options).find((option) => option.value === value)?.dataset.prefix
  }
}
