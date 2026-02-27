import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["caldavFields", "localInfo", "submitButton", "submitText", "providerRadio"]

  connect() {
    this.toggleProvider()
  }

  toggleProvider() {
    const selectedProvider = this.providerRadioTargets.find(radio => radio.checked)?.value

    if (selectedProvider === "local") {
      this.caldavFieldsTarget.classList.add("hidden")
      this.localInfoTarget.classList.remove("hidden")
      this.submitTextTarget.textContent = "Create Calendar"
    } else {
      this.caldavFieldsTarget.classList.remove("hidden")
      this.localInfoTarget.classList.add("hidden")
      this.submitTextTarget.textContent = "Connect Account"
    }
  }
}
