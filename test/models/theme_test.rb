# frozen_string_literal: true

require "test_helper"

class ThemeTest < ActiveSupport::TestCase
  test "every built-in theme reads: text, the accent and what sits on a button" do
    assert_operator Theme.all.size, :>=, 20

    Theme.all.each do |theme|
      tokens = theme.tokens
      surface = color(tokens["--color-background-secondary"])

      %w[--color-text-primary --color-text-secondary --color-text-tertiary --color-accent
         --color-success --color-warning --color-error].each do |name|
        assert_operator color(tokens[name]).contrast(surface), :>=, 4.5, "#{theme.name} #{name}"
      end

      on_button = color(tokens["--color-text-inverse"])
      assert_operator on_button.contrast(color(tokens["--color-accent-solid"])), :>=, 4.5, "#{theme.name} accent button"
      assert_operator on_button.contrast(color(tokens["--color-error-solid"])), :>=, 4.5, "#{theme.name} danger button"
    end
  end

  test "a theme styles <html>: its colour scheme and every token" do
    theme = Theme.find("tokyo-night")

    assert_equal "Tokyo Night", theme.label
    assert theme.dark?
    assert_match(/\Acolor-scheme: dark; --color-background: #1a1b26; /, theme.style)
    assert_equal "#13141c", theme.chrome_color
  end

  test "a light theme keeps cards on the page colour, a dark one raises them" do
    latte = Theme.find("catppuccin-latte").tokens
    assert_equal latte["--color-background"], latte["--color-surface"]

    night = Theme.find("tokyo-night").tokens
    assert_equal night["--color-background-secondary"], night["--color-surface"]
  end

  test "the version follows the colours" do
    palette = { "background" => "#101010", "foreground" => "#eeeeee", "accent" => "#ff8800" }
    one = Theme.new(name: "mine", palette: palette)
    two = Theme.new(name: "mine", palette: palette.merge("accent" => "#0088ff"))

    assert_equal one.version, Theme.new(name: "mine", palette: palette).version
    assert_not_equal one.version, two.version
  end

  test "a palette needs a background, a foreground and an accent, all hex" do
    assert_nil Theme.clean_palette(nil)
    assert_nil Theme.clean_palette("background" => "#101010", "foreground" => "#eeeeee")
    assert_nil Theme.clean_palette("background" => "red", "foreground" => "#eeeeee", "accent" => "#ff8800")

    cleaned = Theme.clean_palette(background: "#101010", foreground: "#EEEEEE", accent: "#ff8800",
      red: "url(javascript:1)", selection: "#333333", "x; color" => "#000000")
    assert_equal({ "background" => "#101010", "foreground" => "#eeeeee", "accent" => "#ff8800" }, cleaned)
  end

  test "a palette without a mode is light or dark by its background" do
    assert Theme.new(name: "a", palette: { "background" => "#101010", "foreground" => "#eeeeee", "accent" => "#ff8800" }).dark?
    assert_not Theme.new(name: "b", palette: { "background" => "#fafafa", "foreground" => "#111111", "accent" => "#ff8800" }).dark?
  end

  test "a sparse palette still gets status and code colours" do
    theme = Theme.new(name: "bare", palette: { "background" => "#fafafa", "foreground" => "#111111", "accent" => "#3264eb" })

    assert_equal 39, theme.tokens.size
    assert theme.tokens.values.all?(&:present?)
  end

  private

  def color(value)
    Theme::Color.new(value)
  end
end
