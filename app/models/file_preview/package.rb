# frozen_string_literal: true

require "zip"

class FilePreview
  # An .xlsx or a .docx: a zip of XML files, read without believing anything it says of
  # itself. A part is unpacked a small piece at a time and handed to a SAX handler as it
  # comes, so no part is ever held whole. What comes out is counted, per part and for the
  # file, and the clock is looked at with every piece: past a limit, reading stops with
  # TooMuch and the file has nothing to show.
  class Package
    class TooMuch < StandardError; end

    # Everything a file someone sent can be instead of what its name says
    UNREADABLE = [ TooMuch, Zip::Error, Zlib::Error, Nokogiri::XML::SyntaxError, IOError, SystemCallError, EncodingError ].freeze

    # rubyzip makes an object of every file a zip lists, on opening it
    MAX_ENTRIES = 5000
    # How much of the zip is unpacked at a time
    PIECE = 32.kilobytes
    LOCAL_HEADER = 0x04034b50

    # What reading one file may cost, shared by all of its parts
    class Budget
      def initialize(bytes: MAX_UNPACKED_BYTES, seconds: MAX_SECONDS)
        @bytes = bytes
        @until = now + seconds
      end

      def spend(bytes)
        @bytes -= bytes
        raise TooMuch, "unpacks to more than is read" if @bytes.negative?
        raise TooMuch, "takes longer than a page waits" if now > @until
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    # Yields the package, or gives nil when the file is no zip or lists more than is opened
    def self.open(path, budget = Budget.new)
      return unless File.open(path, "rb") { |file| Zip::CentralDirectory.new.count_entries(file) } <= MAX_ENTRIES

      Zip::File.open(path) { |zip| yield new(zip, budget) }
    rescue *UNREADABLE
      nil
    end

    def initialize(zip, budget)
      @zip = zip
      @budget = budget
    end

    # Reads a part into a handler (a Nokogiri::XML::SAX::Document that also answers
    # `done?`) and gives the handler back, or nil when the zip has no such part
    def read(name, handler)
      entry = @zip.find_entry(name)
      return unless entry&.file?

      parser = Nokogiri::XML::SAX::PushParser.new(handler)
      unpacked = 0
      unpack(entry) do |piece|
        unpacked += piece.bytesize
        raise TooMuch, "#{name} unpacks to more than is read" if unpacked > MAX_PART_BYTES
        @budget.spend(piece.bytesize)
        parser << piece
        break if handler.done?
      end
      parser.finish unless handler.done?
      handler
    rescue Nokogiri::XML::SyntaxError
      # What comes after all that is shown doesn't have to be right
      handler.done? ? handler : raise
    end

    private

    # A part's bytes as they come out of the zip, some kilobytes at a time. Not through
    # rubyzip's own stream: that unpacks 32 KB of the zip in one go, which can be 33 MB,
    # and what a part says of its size isn't looked at at all.
    def unpack(entry, &block)
      entry.get_raw_input_stream do |file|
        file.seek(entry.local_header_offset)
        signature, _, flags, packing, _, _, _, _, _, name, extra = file.read(30).to_s.unpack("VvvvvvVVVvv")
        raise Zip::Error, "not a file in a zip" unless signature == LOCAL_HEADER && flags.nobits?(1)

        file.seek(name + extra, IO::SEEK_CUR)
        case packing
        when Zip::COMPRESSION_METHOD_STORE then pieces(file, entry.compressed_size, &block)
        when Zip::COMPRESSION_METHOD_DEFLATE then inflate(file, entry.compressed_size, &block)
        else raise Zip::Error, "packed in a way that isn't read"
        end
      end
    end

    def pieces(file, left)
      while left.positive? && (piece = file.read([ left, PIECE ].min))
        left -= piece.bytesize
        yield piece
      end
    end

    # Zlib hands what it unpacks to a block as it goes, 16 KB at most
    def inflate(file, left, &block)
      inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      pieces(file, left) do |packed|
        inflater.inflate(packed, &block)
        break if inflater.finished?
      end
    ensure
      inflater&.close
    end

    # What the handlers of both kinds of file share: a part is read until `done!`
    class Handler < Nokogiri::XML::SAX::Document
      def done?
        @done
      end

      def done!
        @done = true
      end

      private

      def attribute(attributes, name)
        attributes.find { |attribute| attribute.localname == name }&.value
      end
    end
  end
end
