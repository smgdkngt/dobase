# frozen_string_literal: true

class AltchaController < ApplicationController
  allow_unauthenticated_access

  def challenge
    # The bundled widget (public/altcha.min.js, 1.5) speaks ALTCHA's v1 protocol
    options = Altcha::V1::ChallengeOptions.new(
      hmac_key: altcha_hmac_key,
      max_number: 50_000,
      expires: Time.now + 5.minutes
    )
    render json: Altcha::V1.create_challenge(options)
  end

  private

  def altcha_hmac_key
    Rails.application.secret_key_base.first(32)
  end
end
