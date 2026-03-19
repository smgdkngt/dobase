# frozen_string_literal: true

class AltchaController < ApplicationController
  allow_unauthenticated_access

  def challenge
    options = Altcha::ChallengeOptions.new(
      hmac_key: altcha_hmac_key,
      max_number: 50_000,
      expires: Time.now + 5.minutes
    )
    render json: Altcha.create_challenge(options)
  end

  private

  def altcha_hmac_key
    Rails.application.secret_key_base.first(32)
  end
end
