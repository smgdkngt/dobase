# frozen_string_literal: true

module Demo
  # A thumbnail or preview is made from a file that is already here, so the demo
  # stores it even though visitors can't upload (config/initializers/demo.rb)
  module DerivedImages
    def processed = Demo.allowing_uploads { super }
  end
end
