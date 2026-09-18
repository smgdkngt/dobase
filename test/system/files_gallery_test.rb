# frozen_string_literal: true

require "application_system_test_case"

class FilesGalleryTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
    sign_in_as(@user)
  end

  def upload(name)
    @tool.file_items.create!(name: name, file: {
      io: File.open(Rails.root.join("test/fixtures/files/sample.png")), filename: name, content_type: "image/png"
    })
  end

  test "opening the large view, stepping to the next picture, and closing with Escape" do
    upload("one.png")
    upload("two.png")

    visit tool_files_path(@tool)
    wait_for_turbo
    wait_for_stimulus "gallery"

    click_on "View"

    assert_selector "[data-gallery-target='overlay']"
    assert_text "one.png"
    assert_text "1 / 2"

    find("[data-gallery-target='overlay'] button[title='Next']").click

    assert_text "two.png"
    assert_text "2 / 2"

    page.send_keys :escape

    assert_no_selector "[data-gallery-target='overlay']"
  end

  test "the slideshow advances on its own and stops when paused" do
    upload("one.png")
    upload("two.png")

    visit tool_files_path(@tool)
    wait_for_turbo
    wait_for_stimulus "gallery"

    click_on "View"
    assert_text "1 / 2"

    find("button[title='Play slideshow']").click

    assert_text "2 / 2", wait: 6

    find("[data-gallery-target='overlay'] button[title='Previous']").click
    assert_text "1 / 2"

    # Stepping manually pauses the slideshow, so it doesn't advance again on its own
    sleep 4.5
    assert_text "1 / 2"
  end

  test "a folder with only one picture has no slideshow or step controls" do
    upload("only.png")

    visit tool_files_path(@tool)
    wait_for_turbo
    wait_for_stimulus "gallery"

    click_on "View"

    assert_text "only.png"
    assert_no_selector "button[title='Play slideshow']", visible: true
    assert_no_selector "button[title='Next']", visible: true
  end
end
