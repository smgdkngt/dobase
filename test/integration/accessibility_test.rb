# frozen_string_literal: true

require "test_helper"

# Structure a screen reader navigates by: landmarks, headings and skip link.
# These are page-shape assertions, so they run at the request level.
class AccessibilityTest < ActionDispatch::IntegrationTest
  TOOL_PATHS = {
    project_board: ->(tool) { "/tools/#{tool.id}/board" },
    my_docs:       ->(tool) { "/tools/#{tool.id}/docs" },
    my_files:      ->(tool) { "/tools/#{tool.id}/files" },
    my_todos:      ->(tool) { "/tools/#{tool.id}/todo" }
  }.freeze

  setup { sign_in_as users(:one) }

  test "every page has exactly one main landmark" do
    each_page do |path|
      assert_select "main", count: 1, message: "#{path} should have exactly one <main>"
    end
  end

  test "the skip link points at the main landmark" do
    get_page root_path

    assert_select "a.skip-link[href=?]", "#main-content"
    assert_select "main#main-content"
    # The skip link is the first focusable thing on the page.
    assert_match(/<body[^>]*>\s*<a href="#main-content"/, response.body)
  end

  test "the sidebar is a labelled navigation landmark" do
    get_page root_path

    assert_select "aside.sidebar[aria-label]"
    assert_select "aside.sidebar nav[aria-label=?]", "Tools"
  end

  test "every page starts its headings at h1 and skips no level" do
    each_page do |path|
      # A dialog is its own heading scope — it opens with its own h2 — so the
      # page's outline is the headings outside every <dialog>.
      document = Nokogiri::HTML(response.body)
      document.css("dialog").remove
      levels = document.css("h1, h2, h3, h4, h5, h6").map { |heading| heading.name[1].to_i }
      next if levels.empty?

      assert_equal 1, levels.first, "#{path} starts its headings at h#{levels.first}"
      levels.each_cons(2) do |previous, current|
        assert current <= previous + 1, "#{path} skips from h#{previous} to h#{current}"
      end
    end
  end

  test "the current tool is marked aria-current in the sidebar" do
    tool = tools(:project_board)

    get_page "/tools/#{tool.id}/board"

    assert_select "a[href=?][aria-current=?]", "/tools/#{tool.id}", "page"
  end

  test "icon-only buttons carry an accessible name" do
    get_page "/tools/#{tools(:my_todos).id}/todo"

    document = Nokogiri::HTML(response.body)
    unnamed = document.css("button, a[href]").reject do |element|
      element.text.strip.present? ||
        element["aria-label"].present? ||
        element["aria-labelledby"].present? ||
        element["title"].present? ||
        element.css("img[alt]").any? { |image| image["alt"].present? }
    end

    assert_empty unnamed.map { |element| element.to_html.squish.first(120) }
  end

  private

  # Signed-in visits can bounce through a redirect (root goes to the last page
  # the user was on), so follow one before looking at the markup.
  def get_page(path)
    get path
    follow_redirect! while response.redirect?
    assert_response :success, "#{path} did not render"
  end

  def each_page
    paths = [ root_path, tools_path, new_tool_path ]
    TOOL_PATHS.each { |fixture, path_for| paths << path_for.call(tools(fixture)) }

    paths.each do |path|
      get_page path
      yield path
    end
  end
end
