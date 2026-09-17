# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tool = Tool.create!(name: "Launch Plan", tool_type: tool_types(:board), owner: users(:one))
    @invitation = @tool.invitations.create!(email: "newcomer@example.com", invited_by: users(:one))
  end

  test "signing up through an invitation uses the invited address and joins the tool" do
    get invitation_acceptance_path(token: @invitation.token)
    assert_redirected_to signup_path

    get signup_path
    assert_select "input[name='user[email_address]'][value='newcomer@example.com'][readonly]"

    assert_difference -> { User.count }, 1 do
      post signup_path, params: { user: new_user_params(email_address: "somebody-else@example.com"), altcha: altcha_payload }
    end

    user = User.order(:id).last
    assert_equal "newcomer@example.com", user.email_address
    assert_redirected_to tool_path(@tool)
    assert @tool.accessible_by?(user)
  end

  test "sign-up hands out a verification challenge the widget can solve" do
    get altcha_challenge_path

    assert_response :success
    assert_equal %w[algorithm challenge maxnumber salt signature], response.parsed_body.keys.sort
  end

  test "sign-up without a solved verification is refused" do
    get invitation_acceptance_path(token: @invitation.token)

    assert_no_difference -> { User.count } do
      post signup_path, params: { user: new_user_params, altcha: Base64.strict_encode64({ number: 1 }.to_json) }
    end

    assert_response :unprocessable_entity
  end

  test "an expired invitation doesn't open sign-up" do
    get invitation_acceptance_path(token: @invitation.token)
    @invitation.update!(expires_at: 1.minute.ago)

    assert_no_difference -> { User.count } do
      post signup_path, params: { user: new_user_params, altcha: altcha_payload }
    end

    assert_redirected_to login_path
  end

  test "a rate-limited sign-up redirects to the sign-up form instead of erroring" do
    # rate_limit's store defaults to the controller's cache_store, captured
    # once as a plain value when the class body first runs — by then the test
    # environment's null store (which never actually counts anything) is
    # baked in for good, so reassigning Rails.cache later has no effect.
    # Swap in a real store and reload the controller so the limit can trip.
    previous_store = ActionController::Base.cache_store
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    reload_registrations_controller!

    10.times { post signup_path, params: { user: { email_address: "spam@example.com" } } }

    assert_nothing_raised do
      post signup_path, params: { user: { email_address: "spam@example.com" } }
    end
    assert_redirected_to signup_path
    assert_equal "Too many attempts. Try again later.", flash[:alert]
  ensure
    ActionController::Base.cache_store = previous_store
    reload_registrations_controller!
  end

  private

  def reload_registrations_controller!
    Object.send(:remove_const, :RegistrationsController) if Object.const_defined?(:RegistrationsController)
    load Rails.root.join("app/controllers/registrations_controller.rb").to_s
  end

  def new_user_params(email_address: "newcomer@example.com")
    { first_name: "New", last_name: "Comer", email_address: email_address, password: "a-long-password", password_confirmation: "a-long-password" }
  end

  def altcha_payload
    challenge = Altcha::V1.create_challenge(Altcha::V1::ChallengeOptions.new(hmac_key: Rails.application.secret_key_base.first(32), number: 7, max_number: 10))
    Base64.strict_encode64({ algorithm: challenge.algorithm, challenge: challenge.challenge, number: 7, salt: challenge.salt, signature: challenge.signature }.to_json)
  end
end
