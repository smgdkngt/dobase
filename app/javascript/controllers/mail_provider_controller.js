import { Controller } from "@hotwired/stimulus"
import { providerOfAddress, providerOfServer } from "services/mail_providers"

// The mail setup form's choice of service (Mails::Provider): a known one fills in the
// servers, folds them away and says where its app password is made; Other opens them.
// The address goes into the username while nobody typed one of their own.
export default class extends Controller {
  static targets = [ "choice", "hintBox", "hint", "appPasswordLink", "servers", "serversSummary", "address", "username",
                     "imapHost", "imapPort", "imapSsl", "smtpHost", "smtpPort", "smtpTls", "smtpAuth" ]
  static values = { presets: Object }

  connect() {
    this._picked = null
    this._usernameFollows = !this.usernameTarget.value || this.usernameTarget.value === this.addressTarget.value
    // A form shown again after a refused login keeps the service it had, and its servers in sight
    const known = providerOfServer(this.imapHostTarget.value, this.presetsValue)
    if (known) this._show(known)
  }

  pick(event) {
    const key = event.currentTarget.dataset.provider
    this._show(key)
    this._fill(key)
  }

  addressTyped() {
    if (this._usernameFollows) this.usernameTarget.value = this.addressTarget.value
    // Until a service is picked, an address of a known one picks it
    if (this._picked) return
    const key = providerOfAddress(this.addressTarget.value, this.presetsValue)
    if (key) {
      this._show(key)
      this._fill(key)
    }
  }

  usernameTyped() {
    this._usernameFollows = this.usernameTarget.value === "" || this.usernameTarget.value === this.addressTarget.value
  }

  // A field the browser wants filled in is in the folded servers: open them, or nothing would say why the form didn't go
  reveal() {
    this.serversTarget.open = true
  }

  _show(key) {
    this._picked = key
    const preset = this.presetsValue[key] || {}
    this.choiceTargets.forEach((choice) => choice.setAttribute("aria-pressed", String(choice.dataset.provider === key)))

    this.hintBoxTarget.hidden = !preset.hint
    this.hintTarget.textContent = preset.hint ? `${preset.hint} ` : ""
    this.appPasswordLinkTarget.href = preset.app_password_url || "#"
  }

  _fill(key) {
    const preset = this.presetsValue[key] || {}
    if (!preset.imap_host) {
      // Another service's servers would be wrong for this one
      if (providerOfServer(this.imapHostTarget.value, this.presetsValue)) {
        this.imapHostTarget.value = ""
        this.smtpHostTarget.value = ""
        this.serversSummaryTarget.textContent = ""
      }
      this.serversTarget.open = true
      return
    }

    this.imapHostTarget.value = preset.imap_host
    this.imapPortTarget.value = String(preset.imap_port)
    this.imapSslTarget.checked = Boolean(preset.imap_ssl)
    this.smtpHostTarget.value = preset.smtp_host || ""
    this.smtpPortTarget.value = String(preset.smtp_port)
    this.smtpTlsTarget.checked = Boolean(preset.smtp_tls)
    this.smtpAuthTarget.value = preset.smtp_auth || "plain"
    this.serversSummaryTarget.textContent = `${preset.imap_host}, ${preset.smtp_host}`
    this.serversTarget.open = false
  }
}
