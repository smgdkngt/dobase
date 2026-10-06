# frozen_string_literal: true

require "test_helper"

# Whatever a page shows or a form does, the API gives or does too: a page that lists
# or shows something has a JSON view that an access token may ask for, and a form
# posts to an action a token may call. So every screen can be drawn by something
# other than these views (the CLI today), and a new screen can't arrive without its
# half of the API.
#
# The screens below are the ones that go without, each for a reason. One that isn't
# listed fails this test: give it a JSON view and `allow_access_tokens`, or list it
# here and say why. One that is listed and has its API now is taken off the list.
class ApiCoverageTest < ActiveSupport::TestCase
  # Nobody is signed in on these, so there is no one for a token to be
  FOR_ANYONE = %w[
    sessions#new
    registrations#new
    passwords#new
    passwords#edit
    two_factor_challenges#new
    invitation_acceptances#show
    demo/joins#show
    tools/files/shares#show
    tools/files/shares/files#show
  ].freeze

  # An account, and the passwords of mail and calendar accounts: never a token's
  # (CLAUDE.md, "JSON API & CLI")
  NEVER_A_TOKENS = %w[
    profiles#edit
    two_factor_setups#new
    tools/mails/accounts#new
    tools/calendars/accounts#new
    tools/calendars/accounts#edit
  ].freeze

  # About the window a browser has open: where it goes when it opens the app, and
  # how its tiles are arranged
  A_BROWSERS_OWN = %w[
    dashboard#index
    workspaces#show
  ].freeze

  # Still to come
  NOT_YET = %w[
    tools/rooms#show
  ].freeze

  # What a form is sent to
  WRITES = { "new" => "create", "edit" => "update" }.freeze

  test "every screen has its half of the API, but for the ones listed" do
    listed = FOR_ANYONE + NEVER_A_TOKENS + A_BROWSERS_OWN + NOT_YET
    without = screens.reject { |controller, action| in_the_api?(controller, action) }
      .map { |controller, action| "#{controller.controller_path}##{action}" }

    assert_empty without - listed, "These screens can't be drawn from the API. Give each a JSON view and " \
      "allow_access_tokens, or list it in #{self.class.name} with the reason it goes without."
    assert_empty listed - without, "These screens are in the API now (or are gone): take them off the list in #{self.class.name}."
  end

  test "what tells a token's actions apart still does" do
    assert token_may?(Tools::BoardsController, "show")
    assert token_may?(ProfilesController, "show")
    assert_not token_may?(ProfilesController, "update")
    assert_not token_may?(WorkspacesController, "show")
  end

  private
    # Every page the app's own controllers draw: an action a browser can GET that has
    # an HTML view
    def screens
      Rails.application.eager_load!

      Rails.application.routes.routes.filter_map do |route|
        next unless route.verb == "GET"

        controller = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
        action = route.defaults[:action]
        next unless controller && controller < ApplicationController && controller.action_methods.include?(action)

        [ controller, action ] if view?(controller, action, :html)
      end.uniq
    end

    def in_the_api?(controller, action)
      if (write = WRITES[action])
        controller.action_methods.include?(write) && token_may?(controller, write)
      else
        view?(controller, action, :json) && token_may?(controller, action)
      end
    end

    def view?(controller, action, format)
      @lookup ||= ActionView::LookupContext.new(ActionController::Base.view_paths)
      @lookup.exists?(action, controller._prefixes, false, [], formats: [ format ])
    end

    # Whether `allow_access_tokens` covers the action: it takes `reject_access_token`
    # off for it. Rails keeps that as the callback's conditions, which is not something
    # it promises to keep this way, so the test above this one says when it stops.
    def token_may?(controller, action)
      callback = controller._process_action_callbacks.find { |candidate| candidate.filter == :reject_access_token }
      return true unless callback

      instance = controller.new
      instance.action_name = action
      matches = ->(condition) { condition.respond_to?(:match?) ? condition.match?(instance) : nil }

      wanted = callback.instance_variable_get(:@if).map(&matches).compact.all?
      skipped = callback.instance_variable_get(:@unless).map(&matches).compact.any?
      !wanted || skipped
    end
end
