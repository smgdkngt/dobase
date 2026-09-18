# frozen_string_literal: true

module BoardsHelper
  # A card's colours, as CSS values. They're kept here rather than in Tailwind classes,
  # which its build would purge for colours only named in the database.
  CARD_COLORS = {
    "red"    => { hex: "#ef4444", text: "#b91c1c", bg_light: "#fef2f2", ring: "#fca5a5" },
    "orange" => { hex: "#f97316", text: "#c2410c", bg_light: "#fff7ed", ring: "#fdba74" },
    "yellow" => { hex: "#facc15", text: "#854d0e", bg_light: "#fefce8", ring: "#fde047" },
    "green"  => { hex: "#22c55e", text: "#15803d", bg_light: "#f0fdf4", ring: "#86efac" },
    "blue"   => { hex: "#3b82f6", text: "#1d4ed8", bg_light: "#eff6ff", ring: "#93c5fd" },
    "purple" => { hex: "#a855f7", text: "#7e22ce", bg_light: "#faf5ff", ring: "#d8b4fe" }
  }.freeze

  def card_colors
    CARD_COLORS
  end

  def card_color(card)
    CARD_COLORS[card.color]
  end
end
