# frozen_string_literal: true

# A public demo instance: visitors try the app in a throwaway workspace of their own,
# without an account. Everything that reaches outside the app (mail, calendar servers,
# public links, invitations) is switched off, and visitors are removed after a day.
# See docs/demo.md.
module Demo
  EMAIL_DOMAIN = "visitors.demo.invalid"
  LIFETIME = 1.day
  # How many visitors can have a workspace at once; the database and disk stay bounded
  MAX_VISITORS = 500
  MAX_TOOLS_PER_VISITOR = 30
  # The demo shares its disk with whatever else runs on the server. Past this, it takes
  # no more changes until the cleanup has made room, whatever a script finds to fill.
  STORAGE_BUDGET = 2.gigabytes

  def self.enabled? = ENV["DEMO_MODE"] == "true"

  def self.full? = visitors.count >= MAX_VISITORS || over_budget?

  def self.over_budget? = enabled? && database_size > STORAGE_BUDGET

  # SQLite keeps recent writes in a -wal file next to the database
  def self.database_size
    path = ActiveRecord::Base.connection_db_config.database.to_s
    [ path, "#{path}-wal" ].sum { |file| File.exist?(file) ? File.size(file) : 0 }
  end

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
