# frozen_string_literal: true

# Opens a web+dobase:// link. An installed app registers that scheme through the
# manifest's protocol_handlers, so `open "web+dobase://tools/12/mails"` shows
# /tools/12/mails in the app window. Only ever a page on this instance.
class ProtocolLinksController < ApplicationController
  SCHEME = /\Aweb[+ ]dobase:/i # a browser that leaves the link unescaped turns + into a space

  def show
    redirect_to path_from(params[:url].to_s)
  end

  private

  def path_from(link)
    return root_path unless link.match?(SCHEME)

    path = link.sub(SCHEME, "").sub(%r{\A/+}, "")
    return root_path if path.include?("\\")

    uri = URI.parse("/#{path}")
    uri.host || uri.scheme ? root_path : uri.to_s
  rescue URI::InvalidURIError
    root_path
  end
end
