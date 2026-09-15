# frozen_string_literal: true

require "test_helper"

module Files
  class SelectionArchiveTest < ActiveSupport::TestCase
    setup do
      @tool = tools(:my_files)
      @documents = file_folders(:documents)
      @readme = file_items(:readme)
      @readme.file.attach(io: StringIO.new("read me first"), filename: "readme.txt", content_type: "text/plain")
      file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
      Item.create!(tool: @tool, folder: file_folders(:nested_folder), name: "notes.txt",
        file: { io: StringIO.new("remember the milk"), filename: "notes.txt", content_type: "text/plain" })
    end

    test "zips the picked files at the top and each picked folder under its own name" do
      assert_equal({
        "readme.txt" => "read me first",
        "Documents/report.pdf" => "quarterly numbers",
        "Documents/Subfolder/notes.txt" => "remember the milk"
      }, zip_contents(archive))
    end

    test "is named after the tool" do
      assert_equal "My Files.zip", archive.filename
    end

    test "counts the picked files and everything in the picked folders against the budget" do
      stub_const(FolderArchive, :MAX_FILES, 3) do
        assert_not archive.too_large?
      end

      stub_const(FolderArchive, :MAX_FILES, 2) do
        assert archive.too_large?
      end
    end

    private

    def archive
      SelectionArchive.new(@tool, folders: [ @documents ], files: [ @readme ])
    end

    def zip_contents(archive)
      Tempfile.create([ "archive", ".zip" ]) do |file|
        archive.write(file.path)
        Zip::File.open(file.path) { |zip| zip.entries.to_h { |entry| [ entry.name, entry.get_input_stream.read ] } }
      end
    end
  end
end
