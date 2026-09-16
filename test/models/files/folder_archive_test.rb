# frozen_string_literal: true

require "test_helper"

module Files
  class FolderArchiveTest < ActiveSupport::TestCase
    setup do
      @tool = tools(:my_files)
      @documents = file_folders(:documents)
      @subfolder = file_folders(:nested_folder)
      file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
      upload "notes.txt", "remember the milk", folder: @subfolder
    end

    test "zips the files of a folder and its subfolders" do
      assert_equal({ "report.pdf" => "quarterly numbers", "Subfolder/notes.txt" => "remember the milk" }, zip_contents(@documents))
    end

    test "is named after the folder" do
      assert_equal "Documents.zip", FolderArchive.new(@documents).filename
    end

    test "leaves out files that have no upload" do
      Item.create!(tool: @tool, folder: @documents, name: "placeholder.txt")

      assert_equal [ "Subfolder/notes.txt", "report.pdf" ], zip_contents(@documents).keys.sort
    end

    test "is too large with more files than the budget allows" do
      assert_not FolderArchive.new(@documents).too_large?

      stub_const(FolderArchive, :MAX_FILES, 1) do
        assert FolderArchive.new(@documents).too_large?
      end
    end

    test "is too large when the files add up to more bytes than the budget allows" do
      total = "quarterly numbers".bytesize + "remember the milk".bytesize

      stub_const(FolderArchive, :MAX_BYTES, total) do
        assert_not FolderArchive.new(@documents).too_large?
      end

      stub_const(FolderArchive, :MAX_BYTES, total - 1) do
        assert FolderArchive.new(@documents).too_large?
      end
    end

    test "leaves out folders that belong to another tool" do
      intruder = Folder.create!(tool: tools(:project_board), parent: @documents, name: "Intruder")
      upload "planted.txt", "not yours", folder: intruder, tool: tools(:project_board)

      assert_equal [ "Subfolder/notes.txt", "report.pdf" ], zip_contents(@documents).keys.sort
    end

    test "names that aren't safe paths become plain file names" do
      upload "../../escape.txt", "up", folder: @documents
      upload "/etc/passwd", "root", folder: @documents
      @subfolder.update_columns(name: "..")

      names = zip_contents(@documents).keys

      assert_includes names, "..-..-escape.txt"
      assert_includes names, "-etc-passwd"
      assert_includes names, "_/notes.txt"
      assert names.none? { |name| name.start_with?("/") || name.split("/").include?("..") }, names.inspect
    end

    test "files with the same name get numbered instead of overwriting each other" do
      upload "report.pdf", "second copy", folder: @documents
      upload "REPORT.pdf", "third copy", folder: @documents

      contents = zip_contents(@documents)

      assert_equal "quarterly numbers", contents["report.pdf"]
      assert_equal [ "REPORT (3).pdf", "report (2).pdf" ], (contents.keys - [ "report.pdf", "Subfolder/notes.txt" ]).sort
      assert_equal [ "quarterly numbers", "second copy", "third copy" ], contents.values_at("report.pdf", "report (2).pdf", "REPORT (3).pdf").sort
    end

    test "finishes when a folder tree loops back on itself" do
      @documents.update_column(:parent_id, @subfolder.id)

      assert_not FolderArchive.new(@documents).too_large?
      assert_equal [ "Subfolder/notes.txt", "report.pdf" ], zip_contents(@documents).keys.sort
    end

    private

    def upload(name, content, folder:, tool: @tool)
      Item.create!(tool: tool, folder: folder, name: name, file: { io: StringIO.new(content), filename: name, content_type: "text/plain" })
    end

    def zip_contents(folder)
      Tempfile.create([ "archive", ".zip" ]) do |file|
        FolderArchive.new(folder).write(file.path)
        Zip::File.open(file.path) { |zip| zip.entries.to_h { |entry| [ entry.name, entry.get_input_stream.read ] } }
      end
    end
  end
end
