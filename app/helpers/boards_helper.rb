# frozen_string_literal: true

module BoardsHelper
  # A card's colours, as CSS values built on the --color-card-* tokens of tokens.css.
  # Those are fixed: a colour is picked to know a card by, so no theme recolours it.
  # They're kept here rather than in Tailwind classes, which its build would purge for
  # colours only named in the database.
  CARD_COLORS = %w[red orange yellow green blue purple].index_with do |name|
    hue = "var(--color-card-#{name})"
    {
      fill: hue,
      text: "var(--color-card-#{name}-text)",
      bg_light: "color-mix(in srgb, #{hue} 14%, transparent)",
      ring: "color-mix(in srgb, #{hue} 40%, transparent)"
    }
  end.freeze

  def card_colors
    CARD_COLORS
  end

  def card_color(card)
    CARD_COLORS[card.color]
  end
end
