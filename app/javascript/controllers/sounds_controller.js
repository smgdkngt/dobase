import { Controller } from "@hotwired/stimulus"
import { play, soundsOn, setSounds } from "services/sound"

// Profile, Notifications: whether this browser plays the app's sounds (services/sound.js),
// and what each of them sounds like
export default class extends Controller {
  static targets = ["on"]

  connect() {
    this.onTarget.checked = soundsOn()
  }

  choose() {
    setSounds(this.onTarget.checked)
    // Switched on is heard at once
    if (this.onTarget.checked) play("done")
  }

  // Also while they are off: this is where you find out whether you want them
  hear({ params }) {
    play(params.name, { always: true })
  }
}
