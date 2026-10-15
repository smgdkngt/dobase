# frozen_string_literal: true

# Opens a web+dobase:// link. An installed app registers that scheme through the
# manifest's protocol_handlers, so `open "web+dobase://tools/12/mails"` shows
# /tools/12/mails in the app window. Only ever a page on this instance.
class ProtocolLinksController < ApplicationController
  def show
    redirect_to ProtocolLink.path(params[:url])
  end
end
