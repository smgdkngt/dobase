module ApplicationHelper
  def app_name = Rails.application.config.x.app.name
  def app_logo_path = Rails.application.config.x.app.logo_path

  # Who wrote something, once they may have deleted their account
  def author_name(user) = user&.name || "Former member"

  # The name a message or comment goes by: its agent's, or its author's
  def poster_name(record) = record.agent? ? record.via : author_name(record.user)

  # An iPhone zooms the page in when a field with text under 16px takes focus, and leaves
  # it zoomed. A maximum scale stops that there, and people can still pinch to zoom; other
  # browsers take pinch zoom away for it, so only the iPhone gets one.
  def viewport_content
    content = "width=device-width,initial-scale=1,viewport-fit=cover"
    request.user_agent.to_s.match?(/iPhone|iPod/) ? "#{content},maximum-scale=1" : content
  end

  # The theme a page is drawn in, or nil for the app's own look: the signed-in
  # person's, or on a page nobody is signed in on (signing in, a shared link) the
  # one this browser last had.
  def current_theme
    return @current_theme if defined?(@current_theme)

    @current_theme = Current.user ? Current.user.theme(browser_scheme) : Theme.for(remembered_appearance["name"], remembered_appearance["colors"])
  end

  # "mono" when the interface is set in the monospace font, by the same rule
  def current_typeface
    (Current.user ? Current.user.typeface : remembered_appearance["typeface"]).presence_in(Theme::TYPEFACES)
  end

  def remembered_appearance
    @remembered_appearance ||= begin
      remembered = JSON.parse(cookies.signed[:theme].to_s)
      remembered.is_a?(Hash) ? remembered : {}
    rescue JSON::ParserError
      {}
    end
  end

  # Says which theme and typeface a page is in; services/theme.js compares it
  def theme_version = Theme.payload(current_theme, current_typeface)[:version]

  # What <html> wears for them; a change later on goes through services/theme.js
  def theme_attributes
    theme = current_theme
    # (follows the system: services/theme.js asks again when that goes light or dark)
    data = { theme_version: theme_version, typeface: current_typeface, theme_follows_system: Current.user&.theme_follows_system? || nil }.compact
    return { data: data } unless theme

    { style: theme.style, data: data.merge(theme: theme.name, theme_mode: theme.mode) }
  end

  # The keys that move tiles around in the workspace go with Alt, and on a Mac with
  # Control and Option: Option alone types letters there, and moves by word. A
  # browser can pick another pair (services/workspace_keys.js keeps it in a cookie).
  # workspace_key("M") is "Ctrl+Opt+M" or "Alt+M".
  #
  # Keys are written in words on a Mac too. The signs for them (⌃ ⌥ ⌘) are on Apple's
  # own keyboards and on few others, and two of them are easily taken for each other.
  WORKSPACE_MODIFIERS = {
    mac: { "ctrl-alt" => [ "Ctrl+Opt", "Control + Option" ], "ctrl-meta" => [ "Ctrl+Cmd", "Control + Command" ], "alt-meta" => [ "Opt+Cmd", "Option + Command" ] },
    other: { "alt" => [ "Alt", "Alt" ], "ctrl-alt" => [ "Ctrl+Alt", "Ctrl + Alt" ] }
  }.freeze

  def workspace_modifiers = WORKSPACE_MODIFIERS[mac? ? :mac : :other]

  # The one this browser chose, or the first
  def workspace_modifier
    cookies[:workspace_keys].presence_in(workspace_modifiers.keys) || workspace_modifiers.keys.first
  end

  def workspace_key(key, shift: false)
    [ workspace_modifiers[workspace_modifier].first, ("Shift" if shift), key ].compact.join("+")
  end

  # A key that goes with Command on a Mac and with Control elsewhere: mod_key("K")
  def mod_key(key, shift: false)
    [ mac? ? "Cmd" : "Ctrl", ("Shift" if shift), key ].compact.join("+")
  end

  # The launcher's key as this keyboard has it
  def launcher_key = mod_key("K")

  def mac?
    request.user_agent.to_s.match?(/Macintosh|Mac OS X/)
  end

  def absolute_url(path)
    return path if path.start_with?("http")
    "#{root_url.chomp('/')}#{path}"
  end

  # The label hue (tokens.css) each tool type is drawn in
  TOOL_TYPE_HUES = {
    "mail" => "red", "calendar" => "orange", "boards" => "yellow", "files" => "green",
    "docs" => "blue", "chat" => "purple", "todos" => "pink", "room" => "cyan"
  }.freeze

  def tool_type_color(tool_type)
    hue = TOOL_TYPE_HUES[tool_type.slug]
    hue ? "var(--color-label-#{hue})" : "var(--color-text-tertiary)"
  end

  def tool_type_description(tool_type)
    tool_type.description
  end

  def browser_name(user_agent)
    return "Unknown browser" if user_agent.blank?

    case user_agent
    when /Edg\//i then "Microsoft Edge"
    when /Chrome\//i then "Google Chrome"
    when /Firefox\//i then "Mozilla Firefox"
    when /Safari\//i then "Safari"
    when /Opera|OPR\//i then "Opera"
    else "Unknown browser"
    end
  end

  def device_icon(user_agent)
    return "monitor" if user_agent.blank?

    case user_agent
    when /iPhone|Android.*Mobile|Mobile/i then "smartphone"
    when /iPad|Tablet/i then "tablet"
    else "monitor"
    end
  end

  # Makes every link in sanitized HTML open in a new tab. The links are found by
  # parsing it: the sanitizer leaves < and > alone inside an attribute, so a
  # title can hold text that looks like a tag, and a search through the string
  # would write into it and break out of its quotes.
  def externalize_links(html, rel: "noopener")
    return html if html.blank?

    fragment = Nokogiri::HTML5.fragment(html.to_s)
    fragment.css("a").each do |link|
      link["target"] = "_blank"
      link["rel"] = rel
    end
    fragment.to_html.html_safe
  end

  # Returns attribution text like "Created by Alice · Edited by Bob"
  # Only includes names that differ from current_user.
  def attribution_text(record)
    parts = []

    created = record.created_by
    updated = record.updated_by

    if created && created != current_user
      parts << "Created by #{created.name}"
    end

    if updated && updated != current_user && updated != created
      parts << "Edited by #{updated.name}"
    end

    parts.join(" · ").presence
  end

  # What a tool page needs to say who is here: the tool to listen to, and which
  # of the faces is your own. Everything else about a person comes from the
  # server over the channel, never from the page.
  def presence_attributes
    {
      data: {
        controller: "presence",
        presence_tool_id_value: @tool.id,
        presence_user_id_value: Current.user&.id,
        presence_context_value: @presence_context
      }.compact
    }
  end

  # The pages that draw themselves again when something in their tool changes
  # (live_controller.js): the ones that show what is in a tool. The others show what
  # is new in their own way (chat, a document that is open), are a form, or don't yet
  # (mail).
  LIVE_PAGES = %w[tools/boards#show tools/todos#show tools/files#show tools/docs#show tools/calendars#show].freeze

  # What <main> carries on every page: the arrow keys go through whatever the page
  # marks as an item (arrow_keys_controller.js), and on a tool's page people see each
  # other there, and what any of them changes.
  def main_attributes
    data = @tool&.persisted? ? presence_attributes[:data] : {}
    live = "live" if data.any? && "#{controller_path}##{action_name}".in?(LIVE_PAGES)
    { data: data.merge(controller: [ data[:controller], live, "arrow-keys" ].compact.join(" "), arrow_keys_main_value: true) }
  end

  # The colour beside someone's name where several people work in one place: a
  # caret in a document today. Keyed off the id, so it is the same colour for
  # everyone looking, and the same one tomorrow.
  COLLABORATOR_COLORS = %w[#e5484d #d6409f #8e4ec6 #3e63dd #0091ff #12a594 #46a758 #f76b15].freeze

  def user_color(user)
    COLLABORATOR_COLORS[user.id % COLLABORATOR_COLORS.size]
  end
end
