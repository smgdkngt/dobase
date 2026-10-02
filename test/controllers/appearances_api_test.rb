# frozen_string_literal: true

require "test_helper"

class AppearancesApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = api_headers(@user)
  end

  test "show tells the theme and lists the built-in ones" do
    get appearance_path, headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_nil body["name"]
    assert_equal false, body["custom"]
    assert_equal "default", body["version"]
    assert_includes body["themes"], { "name" => "tokyo-night", "label" => "Tokyo Night", "mode" => "dark" }
  end

  test "update picks a built-in theme" do
    patch appearance_path, params: { theme: "gruvbox" }, headers: @headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "gruvbox", body["name"]
    assert_equal "Gruvbox", body["label"]
    assert_equal "dark", body["mode"]
    assert_equal false, body["custom"]
    assert_match(/--color-background: #282828/, body["style"])
    assert_equal "#7daea3", body["colors"]["accent"]
    assert_equal "gruvbox", @user.reload.theme_name
  end

  test "update takes a palette, which is how a desktop's own theme comes along" do
    colors = { mode: "light", background: "#fdf6e3", foreground: "#586e75", accent: "#268bd2", red: "#dc322f", junk: "x" }

    patch appearance_path, params: { theme: "solarized-light", colors: colors }, headers: @headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "solarized-light", body["name"]
    assert_equal "Solarized Light", body["label"]
    assert_equal "light", body["mode"]
    assert_equal true, body["custom"]
    assert_equal({ "mode" => "light", "background" => "#fdf6e3", "foreground" => "#586e75", "accent" => "#268bd2", "red" => "#dc322f" },
      @user.reload.theme_colors)
  end

  test "a palette under a built-in name wins over the built-in colours" do
    patch appearance_path, params: { theme: "nord", colors: { background: "#000000", foreground: "#ffffff", accent: "#ff0000" } },
      headers: @headers, as: :json

    assert_match(/--color-background: #000000/, response.parsed_body["style"])
  end

  test "a built-in theme's own colours are just the built-in theme" do
    colors = YAML.load_file(Rails.root.join("config/themes.yml")).fetch("nord").except("label")

    patch appearance_path, params: { theme: "nord", colors: colors }, headers: @headers, as: :json

    assert_equal false, response.parsed_body["custom"]
    assert_nil @user.reload.theme_colors
  end

  test "update without a theme goes back to the app's own look" do
    @user.choose_theme("nord")

    patch appearance_path, params: { theme: nil }, headers: @headers, as: :json

    assert_response :success
    assert_nil response.parsed_body["name"]
    assert_nil @user.reload.theme_name
  end

  test "an unknown theme without colours is refused" do
    patch appearance_path, params: { theme: "no-such-theme" }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_match(/Unknown theme/, response.parsed_body["error"])

    patch appearance_path, params: { theme: "mine", colors: { background: "red" } }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "update sets the typeface, and leaves the theme as it is" do
    @user.choose_theme("nord")

    patch appearance_path, params: { typeface: "mono" }, headers: @headers, as: :json

    assert_response :success
    assert_equal "mono", response.parsed_body["typeface"]
    assert_equal "nord", response.parsed_body["name"]
    assert_equal "#{Theme.find("nord").version}+mono", response.parsed_body["version"]

    patch appearance_path, params: { typeface: nil }, headers: @headers, as: :json
    assert_nil response.parsed_body["typeface"]
    assert_nil @user.reload.typeface
    assert_equal "nord", @user.theme_name
  end

  test "a read token can look but not change" do
    headers = api_headers(@user, permission: "read", name: "Read only")

    get appearance_path, headers: headers
    assert_response :success

    patch appearance_path, params: { theme: "nord" }, headers: headers, as: :json
    assert_response :forbidden
  end

  test "a theme for light and one for dark, and each is shown by its scheme" do
    patch appearance_path, params: { theme: "catppuccin-latte", scheme: "light" }, headers: @headers, as: :json
    patch appearance_path, params: { theme: "tokyo-night", scheme: "dark" }, headers: @headers, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["follows_system"]
    assert_equal({ "name" => "catppuccin-latte", "label" => "Catppuccin Latte" }, body["light"])
    assert_equal({ "name" => "tokyo-night", "label" => "Tokyo Night" }, body["dark"])
    assert_equal "tokyo-night", body["name"]

    get appearance_path, headers: @headers
    assert_equal "catppuccin-latte", response.parsed_body["name"]

    get appearance_path(scheme: "dark"), headers: @headers
    assert_equal "tokyo-night", response.parsed_body["name"]
    assert_equal "dark", response.parsed_body["mode"]
  end

  test "follow_system turns two themes on and off, and a theme without a scheme is one theme" do
    patch appearance_path, params: { theme: "nord" }, headers: @headers, as: :json
    patch appearance_path, params: { follow_system: true }, headers: @headers, as: :json

    body = response.parsed_body
    assert_equal true, body["follows_system"]
    assert_equal "Dobase", body["light"]["label"]
    assert_equal "nord", body["dark"]["name"]

    patch appearance_path, params: { theme: "gruvbox" }, headers: @headers, as: :json
    assert_equal false, response.parsed_body["follows_system"]
    assert_nil response.parsed_body["dark"]
    assert_equal "gruvbox", @user.reload.theme("dark").name
  end
end
