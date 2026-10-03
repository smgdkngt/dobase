# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :access_tokens, dependent: :destroy
  has_one :workspace_layout, dependent: :delete

  has_many :owned_tools, class_name: "Tool", foreign_key: :owner_id, dependent: :destroy
  # Runs before the dependent: :destroy above, so a tool someone else still owns
  # survives the account that created it.
  before_destroy :hand_over_co_owned_tools, prepend: true
  has_many :collaborations, class_name: "Collaborator", dependent: :destroy
  has_many :board_column_collapses, class_name: "Boards::ColumnCollapse", dependent: :delete_all
  has_many :sidebar_groups, -> { order(:position) }, class_name: "Sidebar::Group", dependent: :destroy

  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"

  NOTIFICATION_LIMIT = 100
  NOTIFICATION_DIGEST_OPTIONS = %w[off 1_hour 2_hours 4_hours daily].freeze

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true

  def name = "#{first_name} #{last_name}".strip

  # The colours this person sees the app in: a palette of their own, a built-in
  # theme, or nil for the app's own look. Someone can have one theme for when their
  # system is light and one for when it is dark (theme_follows_system); then the
  # browser's scheme ("light" or "dark") says which, and nobody's is the light one.
  def theme(scheme = nil)
    return Theme.find(dark_theme_name) if theme_follows_system? && scheme.to_s == "dark"

    Theme.for(theme_name, theme_colors)
  end

  # Takes a built-in theme's name, or a name with a palette. Anything else (nil, an
  # unknown name, a palette that isn't one) goes back to the app's own look.
  #
  # Without a scheme it is the one theme, whatever the system says. With "light" or
  # "dark" it is the theme for that, and the other keeps its own. The dark one is a
  # built-in theme or the app's own dark look; a palette of one's own is the light
  # or the only one.
  def choose_theme(name, colors = nil, scheme: nil)
    palette = Theme.clean_palette(colors)
    mode = colors.to_h.transform_keys(&:to_s)["mode"] if palette
    name = name.to_s.strip.first(60)
    # A desktop on a stock theme sends the colours the built-in one already has
    palette = nil if palette && Theme.find(name)&.style == Theme.new(name: name, palette: palette, mode: mode).style

    chosen = if name.present? && palette
      { theme_name: name, theme_colors: palette.merge("mode" => mode).compact }
    else
      { theme_name: Theme.find(name)&.name, theme_colors: nil }
    end

    case scheme.to_s
    when "dark" then update!(dark_theme_name: Theme.find(name)&.name, theme_follows_system: true)
    when "light" then update!(chosen.merge(theme_follows_system: true))
    else update!(chosen.merge(theme_follows_system: false, dark_theme_name: nil))
    end
    broadcast_theme
  end

  # One theme for light and one for dark, or one for both again. What the browser
  # that asks shows at that moment (seen_in: its scheme) stays what it shows: a dark
  # theme that was the only one becomes the one for dark, and going back to one theme
  # keeps the one that is on.
  def follow_system(on, seen_in: nil)
    return if on == theme_follows_system?

    if on
      dark = theme if theme_colors.blank? && theme&.mode == "dark"
      update!(theme_follows_system: true, dark_theme_name: dark&.name, theme_name: (dark ? nil : theme_name))
    elsif seen_in.to_s == "dark"
      update!(theme_follows_system: false, theme_name: dark_theme_name, theme_colors: nil, dark_theme_name: nil)
    else
      update!(theme_follows_system: false, dark_theme_name: nil)
    end
    broadcast_theme
  end

  # What an avatar falls back to, the same two letters the avatar partial draws
  def initials = "#{first_name.to_s.first}#{last_name.to_s.first}".upcase

  # How those two letters are drawn: in one of the theme's label colours, over a
  # shape in a second one. Always the same for the same person, and spread so that
  # the people of one team seldom look alike (shared/avatar, components.css).
  AVATAR_HUES = %w[red orange yellow green cyan blue purple pink].freeze
  AVATAR_PATTERNS = 6

  def avatar_look
    seed = Zlib.crc32("avatar-#{id}")
    hue = seed % AVATAR_HUES.size
    second = (hue + 1 + (seed / AVATAR_HUES.size) % (AVATAR_HUES.size - 1)) % AVATAR_HUES.size

    { hue: AVATAR_HUES[hue], second: AVATAR_HUES[second], pattern: (seed / 64) % AVATAR_PATTERNS + 1 }
  end

  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }, allow_nil: true
  validates :notification_digest, inclusion: { in: NOTIFICATION_DIGEST_OPTIONS }
  validate :acceptable_avatar

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Opening what a notification is about reads it: a chat, a card, a document.
  # Notifications keep their subject as GlobalIDs in the event's JSON params;
  # a mention keeps only the page it points at, so it's matched by url.
  def read_notifications_about!(records: [], urls: [], types: [])
    patterns = Array(records).map { |record| %("#{record.to_global_id}") } +
      Array(urls).map { |url| %("url":"#{url}") }
    return if patterns.empty?

    # SQLite only reads sanitize_sql_like's backslashes as escapes when told to
    matches = patterns.map { "noticed_events.params LIKE ? ESCAPE '\\'" }.join(" OR ")
    values = patterns.map { |pattern| "%#{self.class.sanitize_sql_like(pattern)}%" }
    scope = notifications.unread.joins(:event).where(matches, *values)
    scope = scope.where(noticed_events: { type: types }) if types.any?
    read = Noticed::Notification.where(id: scope.select(:id)).update_all(read_at: Time.current)
    return if read.zero?

    # The bell counts what's left, on every page this person has open
    ActionCable.server.broadcast("notifications:#{id}", { type: "unread_count", count: notifications.unread.count })
  end

  # "mono" sets the whole interface in the monospace font; anything else is the app's own
  def choose_typeface(name)
    update!(typeface: name.to_s.presence_in(Theme::TYPEFACES))
    broadcast_theme
  end

  # Every page this person has open takes the new colours and typeface at once
  # (with a theme for light and one for dark, each page asks for its own: only the
  # browser knows which of the two it is)
  def broadcast_theme
    payload = Theme.payload(theme, typeface) unless theme_follows_system?
    ActionCable.server.broadcast("notifications:#{id}", { type: "theme", theme: payload }.compact)
  end

  # Unread mail in the inboxes of the user's mail tools, counted like the sidebar counts it
  def unread_mail_count
    Mails::Message.inbox.not_archived.unread.joins(:account).where(mail_accounts: { tool_id: collaborations.select(:tool_id) }).count
  end

  def prune_notifications!
    cutoff_id = notifications.order(created_at: :desc, id: :desc)
                             .offset(NOTIFICATION_LIMIT).limit(1).pick(:id)
    return unless cutoff_id

    notifications.where("id <= ?", cutoff_id).delete_all
  end

  def digest_interval
    case notification_digest
    when "1_hour"  then 1.hour
    when "2_hours" then 2.hours
    when "4_hours" then 4.hours
    when "daily"   then 1.day
    end
  end

  def accessible_tools
    Tool.joins(:collaborators).where(collaborators: { user_id: id }).distinct
  end

  # Accessible tools in this user's own sidebar order, which lives on their
  # collaborator record so it is theirs alone.
  def sidebar_tools
    Tool.joins(:collaborators).where(collaborators: { user_id: id })
        .order(Collaborator.arel_table[:sidebar_position].asc, Tool.arel_table[:id].asc)
  end

  def ungrouped_tools
    grouped_ids = sidebar_groups.joins(:memberships).pluck("sidebar_memberships.tool_id")
    scope = sidebar_tools.includes(:tool_type, :mail_account)
    grouped_ids.any? ? scope.where.not(id: grouped_ids) : scope
  end

  # --- Two-factor authentication ---

  RECOVERY_CODE_COUNT = 8

  def otp
    ROTP::TOTP.new(otp_secret, issuer: Rails.application.config.x.app.name)
  end

  def otp_provisioning_uri
    otp.provisioning_uri(email_address)
  end

  def verify_otp(code)
    return false if otp_secret.blank?

    otp.verify(code.to_s.delete(" "), drift_behind: 15, drift_ahead: 15).present?
  end

  def verify_recovery_code(code)
    return false if otp_recovery_codes.blank?

    codes = JSON.parse(otp_recovery_codes)
    match_index = codes.index { |hashed| BCrypt::Password.new(hashed) == code.to_s.strip.downcase }
    return false unless match_index

    codes.delete_at(match_index)
    update_column(:otp_recovery_codes, codes.to_json)
    true
  end

  def generate_recovery_codes
    plain_codes = RECOVERY_CODE_COUNT.times.map { SecureRandom.hex(4) }
    hashed = plain_codes.map { |c| BCrypt::Password.create(c).to_s }
    update_column(:otp_recovery_codes, hashed.to_json)
    plain_codes
  end

  private

  def hand_over_co_owned_tools
    owned_tools.find_each do |tool|
      successor = tool.collaborators.owners.where.not(user_id: id).order(:created_at, :id).first
      tool.update_column(:owner_id, successor.user_id) if successor
    end
  end

  def acceptable_avatar
    return unless avatar.attached?
    unless avatar.content_type.in?(%w[image/png image/jpeg image/gif image/webp])
      errors.add(:avatar, "must be an image (PNG, JPEG, GIF, or WebP)")
    end
    if avatar.byte_size > 5.megabytes
      errors.add(:avatar, "must be less than 5MB")
    end
  end
end
