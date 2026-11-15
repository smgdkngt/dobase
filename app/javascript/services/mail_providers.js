// The mail services the setup form knows (Mails::Provider): which one an address
// belongs to, and which one a form's servers already are.

/**
 * @typedef {{ domains?: string[], imap_host?: string, imap_port?: number, imap_ssl?: boolean,
 *   smtp_host?: string, smtp_port?: number, smtp_tls?: boolean, smtp_auth?: string,
 *   app_password_url?: string, hint?: string }} Preset
 * @typedef {Record<string, Preset>} Presets
 */

/**
 * The service whose mail an address is, by its domain: "ann@icloud.com" is iCloud's
 * @param {string} address
 * @param {Presets} presets
 * @returns {string | null}
 */
export function providerOfAddress(address, presets) {
  const domain = address.trim().toLowerCase().split("@")[1]
  if (!domain) return null
  return Object.keys(presets).find((key) => (presets[key].domains || []).includes(domain)) || null
}

/**
 * The service whose servers a form has filled in already (a form shown again after a
 * refused login), or null
 * @param {string} imapHost
 * @param {Presets} presets
 * @returns {string | null}
 */
export function providerOfServer(imapHost, presets) {
  const host = imapHost.trim().toLowerCase()
  if (!host) return null
  return Object.keys(presets).find((key) => presets[key].imap_host === host) || null
}
