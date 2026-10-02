# frozen_string_literal: true

require "test_helper"

class LogosControllerTest < ActionDispatch::IntegrationTest
  test "the logo comes as a picture in the two colours asked for, to anyone" do
    # A mail client: nobody signed in, and no browser the app knows
    get logo_path("7aa2f7-1a1b26", format: :png), headers: { "User-Agent" => "Mozilla/5.0 (via ggpht.com GoogleImageProxy)" }

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_match(/max-age=31\d{6}, public/, response.headers["Cache-Control"])

    picture = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 96, 96 ], [ picture.width, picture.height ]
    # The square in the first colour, the letter in the second
    assert_equal [ 0x7a, 0xa2, 0xf7 ], picture.getpoint(80, 12).first(3).map(&:round)
    assert_equal [ 0x1a, 0x1b, 0x26 ], picture.getpoint(24, 48).first(3).map(&:round)
  end

  test "anything but two hex colours and a png is not found" do
    [ "7aa2f7", "7aa2f7-1a1b2", "red-blue", "7aa2f7-1a1b26-ffffff", "%3Csvg%3E-000000" ].each do |colors|
      get "/logos/#{colors}.png"
      assert_response :not_found, colors
    end

    get "/logos/7aa2f7-1a1b26"
    assert_response :not_found

    get "/logos/7aa2f7-1a1b26.svg"
    assert_response :not_found
  end
end
