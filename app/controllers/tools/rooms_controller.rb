# frozen_string_literal: true

module Tools
  class RoomsController < ApplicationController
    include ToolScoped

    def show
      @room = @tool.room
    end
  end
end
