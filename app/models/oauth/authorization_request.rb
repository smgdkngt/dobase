# frozen_string_literal: true

module Oauth
  # What a client sends to the consent page, checked in the order OAuth 2.1
  # asks: an unknown client or redirect is told to the person and never
  # redirected to; anything wrong after that goes back to the client.
  class AuthorizationRequest
    FIELDS = %i[client_id redirect_uri response_type code_challenge code_challenge_method state scope resource].freeze

    attr_reader :params, :client, :error

    def initialize(params)
      @params = params
      @client = Client.find_by(uid: params[:client_id].to_s)
    end

    def redirect_trusted?
      client.present? && client.redirect_uri?(redirect_uri)
    end

    def valid?
      @error = if params[:response_type] != "code"
        "unsupported_response_type"
      elsif params[:code_challenge].blank? || params[:code_challenge_method] != "S256"
        "invalid_request"
      end
      @error.nil?
    end

    def redirect_uri
      params[:redirect_uri].to_s
    end

    def code_challenge
      params[:code_challenge].to_s
    end

    # Where the client is, as a person would recognise it
    def destination
      host = URI.parse(redirect_uri).host
      Oauth::LOOPBACK_HOSTS.include?(host) ? "a program on your computer" : host
    end

    def redirect_with(issuer:, **result)
      uri = URI.parse(redirect_uri)
      extra = { **result, state: params[:state].presence, iss: issuer }.compact.map { |key, value| [ key.to_s, value ] }
      uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + extra)
      uri.to_s
    end

    # What the consent form sends back, so its second step checks the same things
    def form_fields
      FIELDS.index_with { |field| params[field].to_s }.compact_blank
    end
  end
end
