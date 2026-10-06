# frozen_string_literal: true

require "test_helper"
require_relative "comparison"

class ScreenshotComparisonTest < ActiveSupport::TestCase
  setup do
    @shots = Pathname.new(Dir.mktmpdir("shots"))
    picture "before/board"
    picture "after/board"
  end

  teardown { FileUtils.rm_rf(@shots) }

  test "the same pictures are the same" do
    picture "before/phone/mail", colour: [ 20, 30, 40 ]
    picture "after/phone/mail", colour: [ 20, 30, 40 ]

    comparison = compare

    assert comparison.same?
    assert_equal "All 2 scenes are the same.", comparison.report
    assert_not @shots.join("before-after").exist?
  end

  test "one pixel that changed is found, counted and drawn" do
    picture "after/board", dot: [ 30, 12 ]

    comparison = compare
    scene = comparison.differing.sole

    assert_not comparison.same?
    assert_equal [ "board", :changed, 1 ], [ scene.name, scene.verdict, scene.pixels ]
    assert_in_delta 1.0 / (80 * 40), scene.share
    assert_match(/1 of 1 scenes differ:\n  changed  board\s+1 px\s+0.03%/, comparison.report)

    # Before, after and the marked one side by side, with the mark where the pixel is
    drawn = Vips::Image.new_from_file(@shots.join("before-after/board.png").to_s)
    assert_equal [ 3 * 80 + 2 * 16, 40 ], drawn.size
    assert_equal [ 255, 0, 90 ], drawn.getpoint(2 * (80 + 16) + 30, 12).map(&:to_i)
    assert_not_equal [ 255, 0, 90 ], drawn.getpoint(2 * (80 + 16) + 60, 30).map(&:to_i)
  end

  test "a picture of another size is said to be resized" do
    picture "after/board", size: [ 80, 60 ]

    scene = compare.differing.sole

    assert_equal :resized, scene.verdict
    assert_equal 80 * 20, scene.pixels
  end

  test "a scene only one of the two has is added or removed" do
    picture "before/gone"
    picture "after/workspace/new"

    comparison = compare

    assert_equal [ [ "gone", :removed ], [ "workspace/new", :added ] ], comparison.differing.map { |scene| [ scene.name, scene.verdict ] }
    assert_match(/2 of 3 scenes differ/, comparison.report)
  end

  test "the same picture written another way is the same" do
    image("after/board").write_to_file(@shots.join("after/board.png").to_s, compression: 1)

    assert compare.same?
  end

  test "nothing to compare is not the same" do
    FileUtils.rm_rf(@shots.children)

    comparison = compare

    assert_not comparison.same?
    assert_match(/No pictures/, comparison.report)
  end

  test "pictures of the comparison before this one are gone" do
    picture "after/board", dot: [ 1, 1 ]
    compare
    picture "after/board"

    assert compare.same?
    assert_not @shots.join("before-after").exist?
  end

  private

  def compare
    ScreenshotComparison.new(@shots.join("before").to_s, @shots.join("after").to_s, into: @shots.join("before-after").to_s).run
  end

  def picture(name, size: [ 80, 40 ], colour: [ 250, 250, 250 ], dot: nil)
    image = (Vips::Image.black(*size) + colour).cast(:uchar).copy(interpretation: :srgb)
    image = image.draw_rect([ 0, 0, 0 ], *dot, 1, 1) if dot

    file = @shots.join("#{name}.png")
    file.dirname.mkpath
    image.write_to_file(file.to_s)
  end

  def image(name) = Vips::Image.new_from_file(@shots.join("#{name}.png").to_s)
end
