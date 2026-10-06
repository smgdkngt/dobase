import { Controller } from "@hotwired/stimulus"
import { install, uninstall } from "@github/hotkey"

export default class extends Controller {
  // Not in a tile that is part of the workspace's page: there a key is the tile's
  // you are in (tile_frame_controller.js), where this would make it the page's
  connect() { if (!this.element.closest(".tile-frame")) install(this.element) }
  disconnect() { uninstall(this.element) }
}
