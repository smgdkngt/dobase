# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.worker_src  :self, :blob
    policy.style_src   :self, "'unsafe-inline'"
    policy.frame_src   :self
    policy.connect_src :self, *[ ENV["LIVEKIT_URL"]&.sub(%r{^https?://}, "wss://") ].compact
  end

  # Use a nonce for inline importmap scripts
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforce the policy: inline event handlers and non-nonced inline scripts are
  # blocked, so a DOM-XSS sink can't execute injected JavaScript.
  config.content_security_policy_report_only = false
end
