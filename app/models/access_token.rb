# frozen_string_literal: true

# Personal access token for the JSON API. Only a SHA-256 digest is stored; the
# plaintext token is available on the instance right after creation and is
# never retrievable afterwards.
class AccessToken < ApplicationRecord
  PERMISSIONS = %w[read write].freeze
  PREFIX = "dobase_"
  LAST_USED_PRECISION = 1.minute

  belongs_to :user

  attr_reader :token

  validates :name, presence: true, length: { maximum: 100 }
  validates :permission, inclusion: { in: PERMISSIONS }

  before_validation :generate_token, on: :create

  scope :newest_first, -> { order(created_at: :desc) }

  def self.authenticate(token)
    find_by(token_digest: digest(token)) if token.present?
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def write? = permission == "write"

  # Read tokens may only make safe requests.
  def allows?(request_method)
    write? || request_method.in?(%w[GET HEAD])
  end

  def record_usage
    return if last_used_at&.after?(LAST_USED_PRECISION.ago)

    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    @token = "#{PREFIX}#{SecureRandom.base58(32)}"
    self.token_digest = self.class.digest(@token)
  end
end
