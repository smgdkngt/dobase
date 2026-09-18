# frozen_string_literal: true

# Mail clients lag a decade behind browsers: Gmail and Outlook draw no SVG at
# all. An SVG logo falls back to a PNG lying next to it, and to the app's name
# on its own when there isn't one.
module MailerHelper
  def mailer_logo_path
    path = app_logo_path.to_s
    return path.presence unless path.end_with?(".svg")

    png = path.sub(/\.svg\z/, ".png")
    png if Rails.public_path.join(png.delete_prefix("/")).exist?
  end
end
