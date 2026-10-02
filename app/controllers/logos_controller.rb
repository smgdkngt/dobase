# frozen_string_literal: true

# The app's logo as a PNG in two colours: its square and its letter. A mail in a
# theme shows it (MailerHelper#mailer_logo_url), since mail clients draw no SVG
# and can't be handed colours any other way.
#
# A mail client is nobody signed in, in no particular browser, so this stands
# apart from ApplicationController. All it takes is two hex colours, and it
# answers the same picture for them for good.
class LogosController < ActionController::Base
  COLORS = /\A(\h{6})-(\h{6})\z/
  SIZE = 96

  # The logo as it ships: a white letter on a blue square with round corners. That
  # blue has no red in it, so a pixel's red says how much of it is letter, edges
  # included. (Drawing the SVG instead would need libvips' SVG loader, which is
  # blocked along with every other loader that isn't safe for uploads.)
  TEMPLATE = Rails.public_path.join("icon-512.png")

  def show
    fill, ink = params[:id].to_s.match(COLORS)&.captures
    return head :not_found unless fill && request.format.png?

    expires_in 1.year, public: true
    send_data picture(rgb(fill), rgb(ink)), type: "image/png", disposition: "inline"
  rescue Vips::Error => error
    # The logo in its own colours is better than none
    Rails.error.report(error, handled: true)
    redirect_to "/icon.png"
  end

  private

  def rgb(hex)
    hex.scan(/../).map(&:hex)
  end

  def picture(fill, ink)
    template = Vips::Image.new_from_file(TEMPLATE.to_s).resize(SIZE / 512.0)
    letter = template[0] / 255.0
    bands = fill.zip(ink).map { |from, to| letter * (to - from) + from }

    Vips::Image.bandjoin([ *bands, template[3] ]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
  end
end
