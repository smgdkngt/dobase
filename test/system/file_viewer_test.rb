# frozen_string_literal: true

require "application_system_test_case"

# A file opened from where it hangs: the viewer comes over the page, shows what was read
# out of the file, and goes away again.
class FileViewerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_mail)
    sign_in_as(@user)
  end

  def attach(message, name, content, content_type: "application/octet-stream")
    attachment = message.attachments.create!(filename: name, content_type: content_type, file_size: content.bytesize)
    attachment.file.attach(io: StringIO.new(content), filename: name, content_type: content_type, identify: false)
    attachment
  end

  PICTURE = "dialog#file-viewer[open] img[alt='sample.png']"
  LEVEL = "dialog#file-viewer[open] [data-zoom-target='level']"

  # The picture is 8 by 8 and fits as it is, so its width says how far it is zoomed
  def assert_picture_wide(pixels)
    assert_selector(PICTURE) { |picture| picture.evaluate_script("this.offsetWidth") == pixels }
  end

  def open_picture
    message = mails_messages(:inbox_unread)
    attach(message, "sample.png", file_fixture("sample.png").binread, content_type: "image/png")
    attach(message, "figures.csv", "Month;Total\nOctober;42\n")

    visit tool_mail_path(@tool, message)
    click_link "sample.png"
    assert_selector(PICTURE) { |picture| picture.evaluate_script("this.complete && this.naturalWidth > 0") }
    assert_selector LEVEL, text: "100%"
  end

  def close_and_ask_for(name)
    execute_script(<<~JS, name)
      document.getElementById("file-viewer").close()
      document.querySelector(`a[data-turbo-frame="file_viewer"][title="${arguments[0]}"]`).click()
    JS
  end

  test "a spreadsheet attached to a mail opens over the page, closes, and opens again" do
    message = mails_messages(:inbox_unread)
    attach(message, "budget.xlsx", file_fixture("sample.xlsx").binread)

    visit tool_mail_path(@tool, message)
    click_link "budget.xlsx"

    within "dialog#file-viewer[open]" do
      assert_selector "h2", text: "budget.xlsx"
      assert_selector "td", text: "42.5"
      assert_link "Download"
      click_button "Close"
    end
    assert_no_selector "dialog#file-viewer[open]"

    click_link "budget.xlsx"

    assert_selector "dialog#file-viewer[open] td", text: "42.5"
  end

  # A dialog's "close" event comes a moment after it closed. Closing and clicking in one
  # go puts the click before that event every time, which a person only manages now and then.
  test "a file asked for again the moment the viewer closes is shown" do
    message = mails_messages(:inbox_unread)
    attach(message, "budget.xlsx", file_fixture("sample.xlsx").binread)
    attach(message, "figures.csv", "Month;Total\nOctober;42\n")

    visit tool_mail_path(@tool, message)
    click_link "budget.xlsx"
    assert_selector "dialog#file-viewer[open] td", text: "42.5"

    close_and_ask_for "budget.xlsx"
    assert_selector "dialog#file-viewer[open] td", text: "42.5"

    # Another file, also while the one before it is still being read
    close_and_ask_for "figures.csv"
    close_and_ask_for "budget.xlsx"
    close_and_ask_for "figures.csv"
    assert_selector "dialog#file-viewer[open] td", text: "October"
    assert_no_selector "dialog#file-viewer[open] td", text: "42.5"

    send_keys :escape
    assert_no_selector "dialog#file-viewer[open]"
    assert_no_selector "#file_viewer *", visible: :all
  end

  # Turbo draws a file a moment after it arrived, and closing the viewer can't stop that
  # any more. Closing as the answer comes in puts the close before the drawing every time.
  test "a file that arrives as the viewer closes is not put in the closed viewer" do
    message = mails_messages(:inbox_unread)
    attach(message, "figures.csv", "Month;Total\nOctober;42\n")

    visit tool_mail_path(@tool, message)
    execute_script(<<~JS)
      const viewer = document.getElementById("file-viewer")
      const frame = document.getElementById("file_viewer")
      frame.addEventListener("turbo:before-fetch-response", () => viewer.close(), { once: true })
      frame.addEventListener("turbo:frame-load", () => { document.body.dataset.fileArrived = "" }, { once: true })
      document.querySelector('a[data-turbo-frame="file_viewer"][title="figures.csv"]').click()
    JS

    assert_selector "body[data-file-arrived]"
    assert_no_selector "dialog#file-viewer[open]"
    assert_no_selector "#file_viewer *", visible: :all

    # And it is there when asked for again
    click_link "figures.csv"
    assert_selector "dialog#file-viewer[open] td", text: "October"
  end

  test "a draft's attachment can be looked at while the mail is being written" do
    draft = mails_messages(:draft_message)
    attach(draft, "figures.csv", "Month;Total\nOctober;42\n")

    visit new_tool_mail_path(@tool, draft_id: draft.id)
    click_link "figures.csv"

    assert_selector "dialog#file-viewer[open] td", text: "October"

    send_keys :escape

    assert_no_selector "dialog#file-viewer[open]"
    # Still writing the same mail
    assert_selector "form [data-compose-target='attachmentsList']", visible: :all
  end

  test "a picture is zoomed in on with the buttons and the keys, and back to fit" do
    open_picture
    assert_picture_wide 8

    click_button "Zoom in (+)"
    assert_selector LEVEL, text: "125%"
    assert_picture_wide 10
    assert_selector "dialog#file-viewer .zoom-stage[data-zoomed]"

    # The keyboard is on the button that was pressed, which is in the viewer
    send_keys "+"
    assert_selector LEVEL, text: "150%"
    assert_picture_wide 12

    send_keys "-"
    assert_selector LEVEL, text: "125%"

    send_keys "0"
    assert_selector LEVEL, text: "100%"
    assert_picture_wide 8
    assert_no_selector "dialog#file-viewer .zoom-stage[data-zoomed]"

    # A picture goes no smaller than it fits, and eight times is the most
    assert_selector "dialog#file-viewer [data-zoom-target='out'][aria-disabled='true']"
    7.times { click_button "Zoom in (+)" }
    assert_selector LEVEL, text: "800%"
    assert_picture_wide 64
    assert_selector "dialog#file-viewer [data-zoom-target='in'][aria-disabled='true']"

    find(LEVEL).click
    assert_selector LEVEL, text: "100%"
    assert_picture_wide 8
  end

  test "the wheel with Ctrl zooms in on a picture, and without it is left alone" do
    open_picture

    execute_script(<<~JS, find(PICTURE))
      const turn = (more) => arguments[0].dispatchEvent(new WheelEvent("wheel", { deltaY: -100, bubbles: true, cancelable: true, ...more }))
      document.body.dataset.wheelLeft = turn({})
      document.body.dataset.wheelTaken = !turn({ ctrlKey: true })
    JS

    # A notch of a mouse's wheel is about a third
    assert_selector LEVEL, text: "135%"
    assert_selector "body[data-wheel-left='true'][data-wheel-taken='true']"

    # And a double click goes back to fit, and in from there
    find(PICTURE).double_click
    assert_selector LEVEL, text: "100%"
    find(PICTURE).double_click
    assert_selector LEVEL, text: "200%"
    assert_picture_wide 16
  end

  test "two fingers moved apart zoom in on a picture" do
    open_picture

    execute_script(<<~JS, find(PICTURE))
      const picture = arguments[0]
      const fingers = (type, apart) => {
        const touches = [ -apart / 2, apart / 2 ].map((x, identifier) =>
          new Touch({ identifier, target: picture, clientX: 300 + x, clientY: 300 }))
        picture.dispatchEvent(new TouchEvent(type, { touches, targetTouches: touches, changedTouches: touches, bubbles: true, cancelable: true }))
      }
      fingers("touchstart", 100)
      fingers("touchmove", 150)
      fingers("touchmove", 300)
    JS

    assert_selector LEVEL, text: "300%"
    assert_picture_wide 24
  end

  test "the next file fits again, and a table is zoomed out as well as in" do
    open_picture
    click_button "Zoom in (+)"
    assert_selector LEVEL, text: "125%"

    within("dialog#file-viewer[open]") { click_button "Close" }
    click_link "figures.csv"

    assert_selector "dialog#file-viewer[open] td", text: "October"
    assert_selector LEVEL, text: "100%"

    click_button "Zoom out (-)"
    assert_selector LEVEL, text: "80%"
    assert_selector("dialog#file-viewer[open] .sheet-preview") { |sheet| sheet.evaluate_script("getComputedStyle(this).zoom") == "0.8" }

    send_keys "0"
    assert_selector LEVEL, text: "100%"
    assert_selector("dialog#file-viewer[open] .sheet-preview") { |sheet| sheet.evaluate_script("getComputedStyle(this).zoom") == "1" }
  end
end
