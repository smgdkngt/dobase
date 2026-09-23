# frozen_string_literal: true

# A public demo instance: visitors try the app in a throwaway workspace of their own,
# without an account. Everything that reaches outside the app (mail, calendar servers,
# public links, invitations) is switched off, and visitors are removed after a day.
# See docs/demo.md.
module Demo
  EMAIL_DOMAIN = "visitors.demo.invalid"
  LIFETIME = 1.day

  def self.enabled? = ENV["DEMO_MODE"] == "true"

  def self.visitors
    User.where("email_address LIKE ?", "%@#{EMAIL_DOMAIN}")
  end

  # A visitor, signed up on the spot, with the example workspace to look around in
  def self.create_visitor!
    User.transaction do
      User.create!(
        first_name: "Guest",
        last_name: "Visitor",
        email_address: "visitor-#{SecureRandom.hex(8)}@#{EMAIL_DOMAIN}",
        password: SecureRandom.base58(24)
      ).tap { |visitor| allowing_uploads { Workspace.new(visitor).build } }
    end
  end

  # Visitors can't upload anything: a public demo shouldn't host strangers' files.
  # Only the example workspace brings its own.
  def self.uploads_allowed?
    !enabled? || ActiveSupport::IsolatedExecutionState[:demo_uploads]
  end

  def self.allowing_uploads
    ActiveSupport::IsolatedExecutionState[:demo_uploads] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:demo_uploads] = nil
  end
end
