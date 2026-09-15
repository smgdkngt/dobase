# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session, :access_token

  def user
    session&.user || access_token&.user
  end
end
