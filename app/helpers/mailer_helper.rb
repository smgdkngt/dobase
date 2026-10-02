# frozen_string_literal: true

# Mail clients lag a decade behind browsers: Gmail and Outlook draw no SVG at
# all, and none of them know CSS variables. So a mail carries its colours
# inline: the app's own, or those of the theme its reader has in Dobase.
module MailerHelper
  # The app's own look. Readers in dark mode get the dark set in the layout.
  MAIL_COLORS = {
    page: "#f5f5f7", card: "#ffffff", row: "#f5f5f7", border: "#e8e8ed",
    text: "#1d1d1f", quiet: "#6e6e73", muted: "#86868b",
    link: "#0071e3", button: "#0071e3", on_button: "#ffffff"
  }.freeze

  MAIL_FONTS = {
    nil => "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
    "mono" => "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace"
  }.freeze

  # An SVG logo falls back to a PNG lying next to it, and to the app's name
  # on its own when there isn't one.
  def mailer_logo_path
    path = app_logo_path.to_s
    return path.presence unless path.end_with?(".svg")

    png = path.sub(/\.svg\z/, ".png")
    png if Rails.public_path.join(png.delete_prefix("/")).exist?
  end

  # The logo's address for a mail. In a theme the app's own logo is drawn in the
  # theme's accent (LogosController); a logo of your own stays as it is.
  def mailer_logo_url
    if mail_theme && app_logo_path == "/icon.svg"
      logo_url("#{mail_color(:button).delete('#')}-#{mail_color(:on_button).delete('#')}", format: :png)
    elsif (path = mailer_logo_path)
      absolute_url(path)
    end
  end

  # Who the mail goes to, when that is someone with an account
  def mail_reader
    return @mail_reader if defined?(@mail_reader)

    @mail_reader = User.find_by(email_address: Array(message.to).first.to_s.strip.downcase)
  end

  # The theme the reader has in Dobase, or nil for the app's own look
  def mail_theme
    return @mail_theme if defined?(@mail_theme)

    @mail_theme = mail_reader&.theme
  end

  def mail_color(name)
    (mail_theme ? themed_mail_colors : MAIL_COLORS).fetch(name)
  end

  # The reader's typeface: monospace for someone who has set the app in it
  def mail_font
    MAIL_FONTS.fetch(mail_reader&.typeface.presence_in(Theme::TYPEFACES))
  end

  private

  def themed_mail_colors
    @themed_mail_colors ||= begin
      token = ->(name) { mail_theme.tokens.fetch("--color-#{name}") }
      dark = mail_theme.dark?

      {
        page: dark ? token.("sidebar-bg") : token.("background-secondary"),
        card: dark ? token.("background-secondary") : token.("background"),
        row: dark ? token.("background-tertiary") : token.("background-secondary"),
        border: token.("border-light"),
        text: token.("text-primary"), quiet: token.("text-secondary"), muted: token.("text-tertiary"),
        link: token.("accent"), button: token.("accent-solid"), on_button: token.("text-inverse")
      }
    end
  end
end
