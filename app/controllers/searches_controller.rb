# frozen_string_literal: true

# The workspace searched at once. The command palette loads the HTML into a
# frame as you type; the API and the CLI read the JSON.
class SearchesController < ApplicationController
  allow_access_tokens

  def show
    @search = WorkspaceSearch.new(Current.user, params[:q])

    respond_to do |format|
      # The page is a frame's worth of results; opened on its own it has nothing to sit in
      format.html { turbo_frame_request? ? render(layout: false) : redirect_to(root_path) }
      format.json
    end
  end
end
