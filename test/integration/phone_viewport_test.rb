# frozen_string_literal: true

require "test_helper"

# An iPhone zooms the page in when a field with text under 16px takes focus (the
# chat editor, every input) and leaves it zoomed. A maximum scale stops that on an
# iPhone, where pinch zoom keeps working; elsewhere it would take pinch zoom away.
class PhoneViewportTest < ActionDispatch::IntegrationTest
  IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1"
  ANDROID = "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36"

  setup { sign_in_as users(:one) }

  test "an iPhone doesn't zoom in on a field that takes focus" do
    get tools_path, headers: { "User-Agent" => IPHONE }

    assert_select "meta[name='viewport'][content='width=device-width,initial-scale=1,viewport-fit=cover,maximum-scale=1']"
  end

  test "other browsers keep pinch zoom" do
    get tools_path, headers: { "User-Agent" => ANDROID }
    assert_select "meta[name='viewport'][content='width=device-width,initial-scale=1,viewport-fit=cover']"

    get tools_path
    assert_select "meta[name='viewport'][content='width=device-width,initial-scale=1,viewport-fit=cover']"
  end
end
