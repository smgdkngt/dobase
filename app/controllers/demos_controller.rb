# frozen_string_literal: true

# "Try the demo": a visitor gets a workspace of their own and is signed in to it
class DemosController < ApplicationController
  allow_unauthenticated_access
  before_action :require_demo_mode
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Lots of demos were started from here just now. Try again in a few minutes." }

  def create
    return redirect_to root_path if authenticated?
    return redirect_to new_session_path, alert: "The demo is busy right now. Try again in an hour or so." if Demo.full?

    visitor = Demo.create_visitor!
    start_new_session_for visitor
    redirect_to tool_path(visitor.owned_tools.order(:id).first),
      notice: "Welcome to Moonshot Snacks! This workspace is yours to try things out."
  end

  private

  def require_demo_mode
    head :not_found unless Demo.enabled?
  end
end
