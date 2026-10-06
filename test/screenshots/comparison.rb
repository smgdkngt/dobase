# frozen_string_literal: true

require "fileutils"
require "vips"

# Two folders of pictures of the same scenes (bin/screenshots take), laid beside each
# other: which scenes differ, by how many pixels, and a picture of each that does.
class ScreenshotComparison
  Scene = Struct.new(:name, :verdict, :pixels, :share)

  MARK = [ 255, 0, 90 ].freeze
  MISSING = [ 255, 0, 255 ].freeze
  BETWEEN = 16

  attr_reader :scenes

  def initialize(before, after, into:)
    @before = before
    @after = after
    @into = into
  end

  def run
    FileUtils.rm_rf(@into)
    @scenes = (names_in(@before) | names_in(@after)).sort.map { |name| compare(name) }
    self
  end

  def same? = scenes.any? && differing.empty?

  def differing = scenes.reject { |scene| scene.verdict == :same }

  def report
    return "No pictures in #{@before} or #{@after}: bin/screenshots take <name> first" if scenes.empty?
    return "All #{scenes.size} scenes are the same." if same?

    width = differing.map { |scene| scene.name.length }.max
    lines = differing.map do |scene|
      line = format("  %-8s %-#{width}s", scene.verdict, scene.name)
      scene.pixels ? format("%s  %9s px  %6.2f%%", line, thousands(scene.pixels), scene.share * 100) : line
    end
    [ "#{differing.size} of #{scenes.size} scenes differ:", *lines, "", "Before, after and what changed, side by side: #{@into}" ].join("\n")
  end

  private

  # 1,204
  def thousands(number) = number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

  def names_in(folder) = Dir.glob("**/*.png", base: folder).map { |file| file.delete_suffix(".png") }

  def compare(name)
    before, after = [ @before, @after ].map { |folder| File.join(folder, "#{name}.png") }
    return Scene.new(name, :added) unless File.exist?(before)
    return Scene.new(name, :removed) unless File.exist?(after)
    return Scene.new(name, :same) if FileUtils.identical?(before, after)

    was, is = [ before, after ].map { |file| colours(Vips::Image.new_from_file(file)) }
    resized = was.size != is.size
    was, is = [ was, is ].map { |image| on_canvas(image, [ was.width, is.width ].max, [ was.height, is.height ].max) }

    differs = (was != is).bandor
    pixels = (differs.avg * differs.width * differs.height / 255).round
    return Scene.new(name, :same) if pixels.zero? && !resized

    draw(name, was, is, differs)
    Scene.new(name, resized ? :resized : :changed, pixels, pixels.fdiv(differs.width * differs.height))
  end

  def colours(image)
    image = image.colourspace(:srgb)
    image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?
    image.extract_band(0, n: 3)
  end

  # A picture that is smaller than the other gets the rest in a colour no page has
  def on_canvas(image, width, height)
    image.embed(0, 0, width, height, extend: :background, background: MISSING)
  end

  # Before, after, and after paled with what changed marked on it: a mark a few
  # pixels wide, so one pixel that changed can be found
  def draw(name, was, is, differs)
    marked = differs.rank(5, 5, 24).ifthenelse(MARK, (is * 0.3 + 178).cast(:uchar))
    picture = [ was, is, marked ].reduce { |row, image| row.join(image, :horizontal, shim: BETWEEN, background: [ 255, 255, 255 ]) }

    file = File.join(@into, "#{name}.png")
    FileUtils.mkdir_p(File.dirname(file))
    picture.write_to_file(file)
  end
end
