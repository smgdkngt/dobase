# frozen_string_literal: true

# An ordinary address for a page that opens in the installed app: /app/tools/12/mails
# is /tools/12/mails, in the app. A link in another program (a chat, a mail) goes to
# the browser, and a web+dobase:// link isn't one most programs let you click; this
# page hands the browser on to web+dobase://tools/12/mails, which the app takes (the
# manifest's protocol_handlers, and the app `dobase app install` makes). The tab
# stays behind with a way to go on here instead. A phone has no app that could take
# the link, so there it is the page itself at once.
class AppLinksController < ApplicationController
  allow_unauthenticated_access
  layout "app_link"

  def show
    @page = ProtocolLink.path(ProtocolLink.to(requested_page))
    # Always this page: a page that ends like a file name (report.pdf) isn't a format
    phone? ? redirect_to(@page) : render(formats: :html)
  end

  private
    def requested_page
      [ "/#{params[:path]}", request.query_string.presence ].compact.join("?")
    end
end
