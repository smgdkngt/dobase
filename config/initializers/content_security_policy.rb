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
    policy.script_src  :self, "https://ga.jspm.io", "https://cdn.jsdelivr.net"
    policy.style_src   :self, "'unsafe-inline'"
    policy.frame_src   :self
    policy.connect_src :self, *[ ENV["LIVEKIT_URL"]&.sub(%r{^https?://}, "wss://") ].compact
  end

  # Use a nonce for inline importmap scripts
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report violations without enforcing the policy.
  config.content_security_policy_report_only = true
end
