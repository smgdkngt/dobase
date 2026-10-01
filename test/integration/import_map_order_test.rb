# frozen_string_literal: true

require "test_helper"

# Firefox ignores an import map that comes after a module script has started
# loading, and then "application" can't be resolved and no JavaScript runs at all.
class ImportMapOrderTest < ActionDispatch::IntegrationTest
  test "the import map comes before every module script" do
    get new_session_path
    assert_response :success

    scripts = Nokogiri::HTML5(response.body).css("head script")
    import_map = scripts.index { |script| script["type"] == "importmap" }
    first_module = scripts.index { |script| script["type"] == "module" }

    assert import_map, "no import map on the page"
    assert first_module, "no module script on the page"
    assert_operator import_map, :<, first_module
  end
end
