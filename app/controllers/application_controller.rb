# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  # Before the demo's limits, whose refusals are said in the page's language
  around_action :switch_locale
  include DemoRestricted
  include AnnouncesChanges
  include Translation::Methods

  # Requires Popover API, CSS Anchor Positioning, and Invoker Commands (commandfor)
  allow_browser versions: { safari: 26.2, chrome: 135, firefox: 144, opera: 117, ie: false }

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  around_action :set_time_zone
  after_action :track_last_visited_path
  after_action :remember_theme
  after_action :remember_locale

  helper_method :tile?, :tile_frame, :workspace_wanted?, :browser_scheme

  # A tile that is part of the workspace's own page gets its tool's page without a
  # document around it (layouts/tile_frame); any other frame, what Turbo gives a frame
  layout -> { tile_frame ? "tile_frame" : ("turbo_rails/frame" if turbo_frame_request?) }

  private

  # An Undo button on the notice this request leaves (shared/flash): it sends `params`
  # to `url` with `method`, and `z` presses it while it shows
  def offer_undo(url, method: :post, params: {})
    flash[:undo] = { "url" => url, "method" => method.to_s, "params" => params.stringify_keys }
  end

  # The tiling workspace is how a wide window works; a narrow one (a phone) shows one
  # tool at a time. There is no choosing between them. The cookie is the system
  # tests' own: they try every tool as a page of its own, in a wide window.
  def workspace_wanted?
    !(Rails.env.test? && cookies[:workspace] == "off")
  end

  # Without a pattern that looks for one word after another: a long made-up user
  # agent would keep such a pattern busy
  def phone?
    agent = request.user_agent.to_s
    agent.match?(/iPhone|iPod|Windows Phone/) || (agent.include?("Android") && agent.include?("Mobile"))
  end

  # A tile in the workspace (workspace_controller.js) is a tool's page of its own in
  # a frame, drawn without the sidebar and everything else around a tool. The
  # browser says so when it loads the frame, Turbo inside it with every request.
  def tile?
    request.headers["Sec-Fetch-Dest"] == "iframe" || request.headers["X-Tile"].present? || tile_frame.present?
  end

  # A tile without a document of its own: the tool's page drawn into the workspace's
  # page, in a <turbo-frame> the workspace made for it (services/tool_frame.js). Its
  # id, which is what the answer has to wear.
  def tile_frame
    request.headers["Turbo-Frame"].to_s[/\Atile-[a-z0-9]+\z/]
  end

  # To everything that asks, such a tile's request is for a page, not for a part of one
  def turbo_frame_request?
    super && !tile_frame
  end

  # Back to the page a form was sent from. A tile that is part of the workspace's
  # page sends its forms from the workspace's address, which is no page of its tool
  # (and sends a tile on to the start page). Such a tile goes back to where it is,
  # which the workspace says with every request of a tile's (workspace_controller.js),
  # and to the fallback when nothing usable was said.
  def redirect_back_or_to(fallback_location, **options)
    return super unless tile? && sent_from_the_workspace?

    redirect_to tile_address || fallback_location, **options.except(:allow_other_host)
  end

  def sent_from_the_workspace?
    referer = URI.parse(request.referer.to_s)
    referer.path == workspace_path && (referer.host.nil? || referer.host == request.host)
  rescue URI::InvalidURIError
    false
  end

  # A page of the tool the request is about, on this site, and nothing else
  def tile_address
    address = request.headers["X-Tile-Address"].to_s
    tool_id = address[%r{\A/tools/(\d+)(?:[/?#]|\z)}, 1]
    address if tool_id && tool_id == params[:tool_id].to_s
  end

  # The language a page is in: the signed-in person's, else the one this browser
  # last had (a cookie, so signing out keeps it), else what the browser asks for.
  # The API stays English (Translation).
  def switch_locale(&block)
    I18n.with_locale(page_locale, &block)
  end

  def page_locale
    return I18n.default_locale if access_token_request? || request.format.json?

    chosen = current_user&.locale if user_signed_in?
    Translation.supported(chosen) || Translation.supported(cookies[:locale]) ||
      Translation.from_accept_language(request.headers["Accept-Language"]) || I18n.default_locale
  end

  # The sign-in page has nobody to ask for a language: the browser keeps the person's
  def remember_locale
    return unless current_user && Current.session && request.format.html?

    locale = Translation.supported(current_user.locale)
    return if cookies[:locale] == locale

    locale ? cookies.permanent[:locale] = { value: locale, same_site: :lax } : cookies.delete(:locale)
  end

  def set_time_zone(&block)
    timezone = current_user&.timezone.presence || "UTC"
    Time.use_zone(timezone, &block)
  end

  # Times shown in UTC, which is where every account starts, while the browser says
  # it is somewhere else (time_zone_controller.js keeps a cookie): the zone to offer,
  # as the browser names it and as the app does. Nothing once it was waved away for
  # that zone in this browser.
  def suggested_time_zone
    return @suggested_time_zone if defined?(@suggested_time_zone)

    # A demo visitor's account lasts a day: not worth a question
    return @suggested_time_zone = nil if Demo.enabled?

    @suggested_time_zone = begin
      browser = cookies[:browser_time_zone].to_s
      zone = User.time_zone_for(browser) if current_user && current_user.timezone.in?([ nil, "", "UTC" ])
      if zone && zone != "UTC" && cookies[:time_zone_dismissed] != browser
        { browser: browser.tr("_", " "), zone: zone }
      end
    end
  end
  helper_method :suggested_time_zone

  # Whether this browser's system is light or dark, as it said last (services/theme.js
  # keeps a cookie): which of someone's two themes a page is drawn in. Nothing when
  # it never said.
  def browser_scheme
    cookies[:scheme].presence_in(%w[light dark])
  end

  # The sign-in page and shared links have nobody to ask for a theme, so the
  # browser keeps the one its person has (ApplicationHelper#remembered_theme).
  def remember_theme
    return unless current_user && Current.session && request.format.html?

    worn = current_user.theme(browser_scheme)
    if worn || current_user.typeface.present?
      colors = current_user.theme_colors if worn && worn.name == current_user.theme_name
      theme = { name: worn&.name, colors: colors, typeface: current_user.typeface }.compact.to_json
    end
    return if cookies.signed[:theme] == theme

    if theme
      cookies.signed.permanent[:theme] = { value: theme, httponly: true, same_site: :lax }
    else
      cookies.delete(:theme)
    end
  end

  def record_not_found
    forget_last_visited_path

    if request.format.json?
      render json: { error: "Not found" }, status: :not_found
    elsif turbo_frame_request?
      # A redirect here would answer with a page that has no matching frame, and the
      # frame (a modal, say) would go blank without saying why.
      render partial: "shared/record_not_found", status: :not_found
    else
      redirect_to root_path, alert: _("That item no longer exists.")
    end
  end

  # The dashboard sends people back to the page they were last on. Once the
  # record behind that page is gone, following it only lands here again — and
  # the two would bounce off each other forever.
  def forget_last_visited_path
    return unless current_user&.last_visited_path == request.path

    current_user.update_column(:last_visited_path, nil)
  end

  def track_last_visited_path
    return unless current_user
    # API clients reading a tool shouldn't clear the user's activity dots.
    return if Current.access_token
    return unless request.get? && response.successful?
    # Only a page: a script asking for JSON (a draft looked up) isn't somewhere to go back to
    return unless request.format.html? && response.media_type == "text/html"
    return if request.xhr? || turbo_frame_request?
    return unless request.path.start_with?("/tools")
    return if request.path.match?(%r{/sync\b})
    # Don't treat a file download as a navigational page — otherwise the
    # dashboard would redirect straight back into the download on every visit.
    return if response.headers["Content-Disposition"].to_s.start_with?("attachment")

    # With several tools open as tiles there is no one tool you were last on
    current_user.update_column(:last_visited_path, request.path) unless tile?

    tool_id = request.path.match(%r{/tools/(\d+)})&.[](1)
    if tool_id
      Collaborator.where(user_id: current_user.id, tool_id: tool_id)
                  .update_all(last_seen_at: Time.current)
    end
  end
end
