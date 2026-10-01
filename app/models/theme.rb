# frozen_string_literal: true

# A colour theme: a palette in the names Omarchy's colors.toml uses, and the design
# tokens (the --color-* variables of tokens.css) worked out from it.
#
# The built-in themes are Omarchy's (config/themes.yml). A person can also carry a
# palette of their own, which is how `dobase theme sync` follows whatever theme their
# Omarchy desktop is on. Without a theme the app keeps its own look, light or dark
# with the system.
class Theme
  # What a palette may hold. Only background, foreground and accent are needed;
  # the rest fall back to something derived or to the app's own status colours.
  COLORS = %w[
    background dark_background foreground bright_foreground accent
    red yellow orange green cyan blue magenta
  ].freeze
  REQUIRED = %w[background foreground accent].freeze

  FALLBACKS = {
    "dark" => { "red" => "#ff6961", "yellow" => "#ff9f0a", "green" => "#30d158", "cyan" => "#4eb0cc", "blue" => "#4aa3ff", "magenta" => "#b281eb" },
    "light" => { "red" => "#d70015", "yellow" => "#a35a00", "green" => "#1e7a34", "cyan" => "#0b6a78", "blue" => "#0064d2", "magenta" => "#ad3da4" }
  }.freeze

  # Text has to carry WCAG AA against whatever it sits on
  READABLE = 4.5

  attr_reader :name, :label, :mode, :palette

  class << self
    def all
      @all ||= YAML.load_file(Rails.root.join("config/themes.yml")).map do |name, attributes|
        new(name: name, label: attributes["label"], mode: attributes["mode"], palette: attributes)
      end.sort_by(&:label).freeze
    end

    def find(name)
      all.find { |theme| theme.name == name.to_s }
    end

    # The colours of a palette someone sent, or nil when it can't make a theme
    def clean_palette(colors)
      return unless colors.respond_to?(:to_h)

      palette = colors.to_h.transform_keys(&:to_s).slice(*COLORS)
        .transform_values { |value| value.to_s.strip.downcase }
        .select { |_, value| Color.hex?(value) }
      palette if REQUIRED.all? { |key| palette.key?(key) }
    end

    # What a page needs to put a theme on, or to take one off (nil)
    def payload(theme)
      return { version: "default" } unless theme

      { version: theme.version, name: theme.name, mode: theme.mode, style: theme.style, chrome_color: theme.chrome_color }
    end
  end

  def initialize(name:, palette:, label: nil, mode: nil)
    @name = name.to_s
    @label = label.presence || @name.tr("-_", " ").titleize
    @palette = palette.to_h.slice(*COLORS).transform_values { |hex| Color.new(hex) }
    @mode = %w[light dark].include?(mode) ? mode : (@palette.fetch("background").luminance > 0.4 ? "light" : "dark")
  end

  def dark? = mode == "dark"

  # Changes whenever the look does, so a page can tell its colours are stale
  def version
    @version ||= "#{name}-#{Digest::SHA256.hexdigest(style)[0, 8]}"
  end

  # The sidebar colour, which is what a browser draws its own chrome in
  def chrome_color = tokens["--color-sidebar-bg"]

  # For a style attribute on <html>
  def style
    @style ||= ([ "color-scheme: #{mode}" ] + tokens.map { |name, value| "#{name}: #{value}" }).join("; ")
  end

  # The handful of colours a small preview of the theme is drawn with
  def swatch
    tokens.slice("--color-background", "--color-sidebar-bg", "--color-text-primary", "--color-text-tertiary",
      "--color-border", "--color-accent-solid", "--color-background-secondary")
  end

  def tokens
    @tokens ||= build_tokens.transform_values(&:to_s).freeze
  end

  private

  def build_tokens
    page = palette.fetch("background")
    text = [ palette.fetch("foreground"), palette["bright_foreground"] ].compact.max_by { |color| color.contrast(page) }
    text = text.readable_on(page, 7, dark: dark?)

    # Steps away from the page, towards the text: raised surfaces, hovers, lines
    step = ->(amount) { page.mix(text, amount) }
    secondary = step.(dark? ? 0.07 : 0.045)
    tertiary = step.(dark? ? 0.13 : 0.09)
    readable = ->(color) { color.readable_on(secondary, READABLE, dark: dark?) }

    sidebar = palette["dark_background"] || (dark? ? page.mix(Color::BLACK, 0.25) : step.(0.045))
    sidebar_hover = sidebar.mix(text, 0.08)

    # What sits on a filled accent button: white, or the darkest colour the theme has
    accent = palette.fetch("accent")
    ink = [ page, text ].min_by(&:luminance)
    on_accent = [ Color::WHITE, ink ].max_by { |color| color.contrast(accent) }
    solid = ->(color) { color.readable_under(on_accent, READABLE) }

    red = color("red")
    green = color("green")
    yellow = color("yellow")

    {
      "--color-background" => page,
      "--color-background-secondary" => secondary,
      "--color-background-tertiary" => tertiary,
      "--color-surface" => dark? ? secondary : page,
      "--color-surface-elevated" => dark? ? tertiary : page,

      "--color-text-primary" => text,
      "--color-text-secondary" => readable.(text.mix(page, 0.22)),
      "--color-text-tertiary" => readable.(text.mix(page, 0.36)),
      "--color-text-inverse" => on_accent,

      "--color-border" => step.(dark? ? 0.22 : 0.18),
      "--color-border-light" => step.(dark? ? 0.13 : 0.09),
      "--color-divider" => step.(dark? ? 0.22 : 0.18),

      "--color-accent" => readable.(accent),
      "--color-accent-hover" => readable.(accent).mix(text, 0.2),
      "--color-accent-solid" => solid.(accent),
      "--color-accent-solid-hover" => solid.(accent).mix(on_accent, 0.12),
      "--color-accent-light" => readable.(accent).alpha(0.15),

      "--color-success" => readable.(green),
      "--color-success-light" => green.alpha(0.15),
      "--color-warning" => readable.(yellow),
      "--color-warning-light" => yellow.alpha(0.15),
      "--color-error" => readable.(red),
      "--color-error-solid" => solid.(red),
      "--color-error-light" => red.alpha(0.15),

      "--color-code-comment" => readable.(text.mix(page, 0.45)),
      "--color-code-keyword" => readable.(color("magenta")),
      "--color-code-string" => readable.(green),
      "--color-code-number" => readable.(palette["orange"] || yellow),
      "--color-code-name" => readable.(color("cyan")),
      "--color-code-constant" => readable.(color("blue")),

      "--color-sidebar-bg" => sidebar,
      "--color-sidebar-hover" => sidebar_hover,
      "--color-sidebar-active" => sidebar.mix(text, 0.15),
      "--color-sidebar-text" => text,
      "--color-sidebar-text-muted" => text.mix(sidebar, 0.22).readable_on(sidebar_hover, READABLE, dark: dark?)
    }.merge(shadows)
  end

  def color(name)
    palette[name] || Color.new(FALLBACKS.fetch(mode).fetch(name))
  end

  def shadows
    strength = dark? ? [ 0.3, 0.4, 0.5, 0.6 ] : [ 0.04, 0.08, 0.12, 0.16 ]
    {
      "--shadow-sm" => "0 1px 2px rgba(0, 0, 0, #{strength[0]})",
      "--shadow-md" => "0 4px 12px rgba(0, 0, 0, #{strength[1]})",
      "--shadow-lg" => "0 8px 24px rgba(0, 0, 0, #{strength[2]})",
      "--shadow-xl" => "0 16px 48px rgba(0, 0, 0, #{strength[3]})"
    }
  end
end
