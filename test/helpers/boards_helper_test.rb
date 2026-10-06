# frozen_string_literal: true

require "test_helper"

# A card's colour is picked to know the card by, so it is the same in every theme
class BoardsHelperTest < ActionView::TestCase
  STYLES = Rails.root.join("app/assets/tailwind/tokens.css").read
  SURFACES = %w[--color-surface --color-background --color-background-secondary].freeze

  test "no theme changes a card's colours: the tokens they are made of are fixed" do
    used = BoardsHelper::CARD_COLORS.values.flat_map(&:values).join.scan(/var\((--[\w-]+)\)/).flatten.uniq

    assert_equal BoardsHelper::CARD_COLORS.size * 2, used.size
    used.each do |token|
      assert token.start_with?("--color-card-"), "#{token} is not a card's own colour"
      assert fixed.key?(token), "#{token} has no value in tokens.css"
    end

    (Theme.all + [ own_theme ]).each do |theme|
      assert_empty theme.tokens.keys & used, "#{theme.name} changes a card's colour"
      assert_no_match(/--color-card-/, theme.style, "#{theme.name} changes a card's colour")
    end
  end

  test "a card's colour is the same tint on a light page and on a dark one" do
    BoardsHelper::CARD_COLORS.each_key do |name|
      assert_not dark.key?("--color-card-#{name}"), "#{name} has another fill in the dark"
    end
  end

  test "a dark system and a dark theme write a colour's name in the same tints" do
    assert_equal BoardsHelper::CARD_COLORS.size, dark.size
    assert_equal dark, values_in(':root:not([data-theme-mode="light"])')
  end

  test "a colour's name reads on its own wash, on every theme's surfaces" do
    pages = Theme.all.map { |theme| [ theme.name, theme.mode, theme.tokens.slice(*SURFACES) ] }
    pages << [ "the app's own, light", "light", own_surfaces.transform_values(&:first) ]
    pages << [ "the app's own, dark", "dark", own_surfaces.transform_values(&:last) ]

    pages.each do |page, mode, surfaces|
      BoardsHelper::CARD_COLORS.each_key do |name|
        fill = Theme::Color.new(fixed.fetch("--color-card-#{name}"))
        text = Theme::Color.new((mode == "dark" ? fixed.merge(dark) : fixed).fetch("--color-card-#{name}-text"))

        surfaces.each do |surface, hex|
          wash = Theme::Color.new(hex).mix(fill, 0.14)
          assert_operator text.contrast(wash), :>=, 4.5, "#{name} on #{surface} of #{page}"
        end
      end
    end
  end

  private

  def fixed = @fixed ||= values_in(":root")
  def dark = @dark ||= values_in(':root[data-theme-mode="dark"]')

  # The card colours a rule of tokens.css sets
  def values_in(selector)
    STYLES[/^\s*#{Regexp.escape(selector)} \{(.*?)\}/m, 1].scan(/(--color-card-[\w-]+): (#\h{6});/).to_h
  end

  # The app's own surfaces: light first, dark second
  def own_surfaces
    SURFACES.index_with { |surface| STYLES.scan(/#{surface}: (#\h{6});/).flatten }
  end

  # A palette of someone's own, with every colour a palette may hold
  def own_theme
    Theme.new(name: "own", palette: Theme::COLORS.index_with { "#4a2fd0" }.merge("background" => "#101010", "foreground" => "#eeeeee"))
  end
end
