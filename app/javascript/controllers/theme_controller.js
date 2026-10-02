import { Controller } from "@hotwired/stimulus"
import { refreshTheme, rememberTheme, themeVersion } from "services/theme"

// Keeps <html> in the signed-in person's theme. Turbo swaps <body> and leaves <html>
// as it is, so a theme picked on the profile page, on another device or by the CLI
// arrives as a <body> whose version isn't the one <html> wears.
export default class extends Controller {
  static values = { version: String }

  async versionValueChanged() {
    if (!this.versionValue) return
    if (this.versionValue === themeVersion()) return rememberTheme()
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    await refreshTheme()
  }
}
