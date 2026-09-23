# frozen_string_literal: true

module Demo
  # "Try it together": a link from the demo banner signs a second window (or a friend)
  # in as one of the visitor's teammates, to see each other type, chat and call live.
  # Only a demo teammate can be joined as, never a visitor or anyone with an account.
  class JoinsController < ApplicationController
    allow_unauthenticated_access
    before_action :require_demo_mode
    rate_limit to: 10, within: 3.minutes, only: :create,
      with: -> { redirect_to new_session_path, alert: "Try again in a few minutes." }
    before_action :set_teammate

    def show
      redirect_to workspace_path if authenticated? && current_user == @teammate
    end

    def create
      start_new_session_for @teammate
      redirect_to workspace_path, notice: "You're #{@teammate.name} now. Say hi in the chat!"
    end

    private

    def require_demo_mode
      head :not_found unless Demo.enabled?
    end

    def set_teammate
      @teammate = User.find_signed(params[:token], purpose: :demo_join)
      redirect_to new_session_path, alert: "That link has expired." unless Demo.teammate?(@teammate)
    end

    def workspace_path
      chat = @teammate.accessible_tools.joins(:tool_type).find_by(tool_types: { slug: "chat" })
      chat ? tool_path(chat) : root_path
    end
  end
end
