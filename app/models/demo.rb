# frozen_string_literal: true

# A public demo instance: visitors try the app in a throwaway workspace of their own,
# without an account. Everything that reaches outside the app (mail, calendar servers,
# public links, invitations) is switched off, and visitors are removed after a day.
# See docs/demo.md.
module Demo
  EMAIL_DOMAIN = "visitors.demo.invalid"
  # Each visitor has three teammates of their own, known by the same key in their
  # address: visitor-<key>@visitors.demo.invalid and marcus-<key>@team.demo.invalid.
  TEAM_DOMAIN = "team.demo.invalid"
  PARTY_ADDRESS = /\A[a-z]+-(?<key>\h+)@(?:#{Regexp.escape(EMAIL_DOMAIN)}|#{Regexp.escape(TEAM_DOMAIN)})\z/
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

  def self.teammates
    User.where("email_address LIKE ?", "%@#{TEAM_DOMAIN}")
  end

  def self.teammate?(user) = user&.email_address.to_s.end_with?("@#{TEAM_DOMAIN}")

  # A visitor and their teammates, whichever of them is asking
  def self.party_of(user)
    key = user&.email_address.to_s[PARTY_ADDRESS, :key]
    key ? User.where(email_address: party_addresses(key)) : User.none
  end

  def self.teammates_of(user)
    party_of(user).where("email_address LIKE ?", "%@#{TEAM_DOMAIN}")
  end

  def self.visitor_of(user)
    party_of(user).find_by("email_address LIKE ?", "%@#{EMAIL_DOMAIN}")
  end

  # What a link to join as a teammate carries (Demo::JoinsController)
  def self.join_token(teammate) = teammate.signed_id(purpose: :demo_join, expires_in: LIFETIME)

  # A visitor, signed up on the spot, with teammates of their own and the example
  # workspace to look around in. The teammates come alive for a few minutes.
  def self.create_visitor!
    key = SecureRandom.hex(8)
    visitor = User.transaction do
      visitor = create_user!(first_name: "Guest", last_name: "Visitor", email_address: visitor_address(key))
      teammates = Workspace::TEAMMATES.map do |teammate|
        create_user!(**teammate.slice(:first_name, :last_name), email_address: teammate_address(teammate, key))
      end
      allowing_uploads { Workspace.new(visitor, teammates: teammates).build }
      visitor
    end

    TeammatesJob.start(visitor)
    visitor
  end

  def self.party_addresses(key)
    [ visitor_address(key), *Workspace::TEAMMATES.map { |teammate| teammate_address(teammate, key) } ]
  end

  def self.visitor_address(key) = "visitor-#{key}@#{EMAIL_DOMAIN}"

  def self.teammate_address(teammate, key) = "#{teammate[:first_name].downcase}-#{key}@#{TEAM_DOMAIN}"

  # Nobody knows the password: visitors get in by the demo button, teammates by a join link
  def self.create_user!(**attributes)
    User.create!(**attributes, password: SecureRandom.base58(24))
  end
  private_class_method :create_user!, :party_addresses, :visitor_address, :teammate_address

  # Visitors can't upload anything: a public demo shouldn't host strangers' files.
  # Only the example workspace brings its own.
  def self.uploads_allowed?
    !enabled? || ActiveSupport::IsolatedExecutionState[:demo_uploads]
  end

  def self.allowing_uploads
    allowed = ActiveSupport::IsolatedExecutionState[:demo_uploads]
    ActiveSupport::IsolatedExecutionState[:demo_uploads] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:demo_uploads] = allowed
  end
end
