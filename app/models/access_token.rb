# frozen_string_literal: true

# Personal access token for the JSON API. Only a SHA-256 digest is stored; the
# plaintext token is available on the instance right after creation and is
# never retrievable afterwards.
#
# A connection an MCP client made by OAuth is an access token too, with its
# client (`oauth_client`) and an end (`expires_at`): it is named, listed and
# revoked as one, while the client sends the short-lived tokens of its grants.
class AccessToken < ApplicationRecord
  PERMISSIONS = %w[read write].freeze
  PREFIX = "dobase_"
  LAST_USED_PRECISION = 1.minute
  CONNECTION_LIFETIME = 30.days

  belongs_to :user
  belongs_to :oauth_client, class_name: "Oauth::Client", optional: true
  has_many :oauth_grants, class_name: "Oauth::Grant", dependent: :delete_all

  attr_reader :token

  validates :name, presence: true, length: { maximum: 100 }
  validates :permission, inclusion: { in: PERMISSIONS }

  before_validation :generate_token, on: :create
  # A revoked token stops listening at once (EventsChannel is all it could open)
  after_destroy_commit :close_connections

  scope :newest_first, -> { order(created_at: :desc) }
  scope :personal, -> { where(oauth_client_id: nil) }
  scope :connections, -> { where.not(oauth_client_id: nil) }

  def self.authenticate(token)
    return if token.blank?

    access_token = find_by(token_digest: digest(token)) || Oauth::Grant.authenticate(token)
    access_token unless access_token&.expired?
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def write? = permission == "write"

  def connection? = oauth_client_id.present?

  def expired? = expires_at&.past? || false

  # Read tokens may only make safe requests.
  def allows?(request_method)
    write? || request_method.in?(%w[GET HEAD])
  end

  def record_usage
    return if last_used_at&.after?(LAST_USED_PRECISION.ago)

    update_column(:last_used_at, Time.current)
  end

  private

  def close_connections
    ActionCable.server.remote_connections.where(current_user: user, access_token: self).disconnect(reconnect: false)
    Mcp::Endpoint.running_live&.close_token(id)
  end

  def generate_token
    @token = "#{PREFIX}#{SecureRandom.base58(32)}"
    self.token_digest = self.class.digest(@token)
  end
end
