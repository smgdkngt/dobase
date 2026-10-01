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

  test "a picture uploaded while the page is open shows in the large view" do
    upload("one.png")

    visit tool_files_path(@tool)
    wait_for_turbo
    wait_for_stimulus "gallery"
    wait_for_stimulus "file-upload"

    # Uploading refreshes the page without connecting the gallery again
    find("[data-file-upload-target='input']", visible: :all)
      .attach_file(Rails.root.join("test/fixtures/files/sample.png"), make_visible: true)
    assert_selector "button[aria-label='View sample.png']", visible: :all
    wait_for_turbo

    find("button[aria-label='View sample.png']", visible: :all).execute_script("this.click()")

    within("[data-gallery-target='overlay']") do
      assert_text "sample.png"
      assert_text "2 / 2"
      assert_selector "img[alt='sample.png']"
      assert_selector "button[title='Previous']"
    end
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
