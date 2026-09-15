# frozen_string_literal: true

require "test_helper"
require "zip"

module Tools
  class FilesApiTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @headers = api_headers(@user)
      @tool = tools(:my_files)
      @documents = file_folders(:documents)
      @readme = file_items(:readme)
      @report = file_items(:report)
    end

    test "listing the top level returns its folders and files" do
      get tool_files_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal tool_files_url(@tool), body["url"]
      assert_nil body["folder"]
      assert_equal [], body["breadcrumbs"]
      assert_equal [ "Documents", "Photos" ], body["folders"].map { |folder| folder["name"] }
      assert_equal [ "readme.txt" ], body["files"].map { |file| file["name"] }

      readme = body["files"].first
      assert readme["shared"]
      assert_nil readme["folder_id"]
      assert_equal tool_files_item_url(@tool, @readme), readme["url"]
      assert_equal tool_files_item_download_url(@tool, @readme), readme["download_url"]
      assert_not body["folders"].first["shared"]
    end

    test "listing a folder returns the folder, its breadcrumbs, subfolders and files" do
      subfolder = file_folders(:nested_folder)
      subfolder.children.create!(tool: @tool, name: "Deeper")

      get tool_files_path(@tool, folder_id: subfolder.id), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal({ "id" => subfolder.id, "name" => "Subfolder", "parent_id" => @documents.id }, body["folder"])
      assert_equal [ { "id" => @documents.id, "name" => "Documents", "parent_id" => nil } ], body["breadcrumbs"]
      assert_equal [ "Deeper" ], body["folders"].map { |folder| folder["name"] }
      assert_equal [], body["files"]

      get tool_files_path(@tool, folder_id: @documents.id), headers: @headers

      assert_equal [ "Subfolder" ], response.parsed_body["folders"].map { |folder| folder["name"] }
      assert_equal [ "report.pdf" ], response.parsed_body["files"].map { |file| file["name"] }
    end

    test "listing doesn't store the view preference cookie" do
      get tool_files_path(@tool, view: "list"), headers: @headers

      assert_response :success
      assert_nil response.cookies["files_view"]
    end

    test "show returns the file with its share and never the password" do
      @readme.share.update!(password: "moonshot")

      get tool_files_item_path(@tool, @readme), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal "readme.txt", body["name"]
      assert_equal "text/plain", body["content_type"]
      assert_equal share_url(@readme.share.token), body.dig("share", "url")
      assert body.dig("share", "password_protected")
      assert_equal 3, body.dig("share", "download_count")
      assert_not_includes response.body, "moonshot"
      assert_not_includes response.body, @readme.share.reload.password_digest
    end

    test "show returns a null share for a file that isn't shared" do
      get tool_files_item_path(@tool, @report), headers: @headers

      assert_response :success
      assert_nil response.parsed_body["share"]
      assert_not response.parsed_body["shared"]
    end

    test "update renames a file" do
      patch tool_files_item_path(@tool, @readme), params: { name: "README.md" }, headers: @headers, as: :json

      assert_response :success
      assert_equal "README.md", response.parsed_body["name"]
      assert_equal "README.md", @readme.reload.name
      assert_equal @user, @readme.updated_by
    end

    test "update accepts attributes nested under file, as the web sends them" do
      patch tool_files_item_path(@tool, @readme), params: { file: { name: "notes.txt" } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "notes.txt", @readme.reload.name
    end

    test "update with a blank name returns errors" do
      patch tool_files_item_path(@tool, @readme), params: { name: "" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Name can't be blank"
    end

    test "update moves a file into a folder and back to the top level" do
      patch tool_files_item_path(@tool, @readme), params: { folder_id: @documents.id }, headers: @headers, as: :json

      assert_response :success
      assert_equal @documents.id, response.parsed_body["folder_id"]
      assert_equal @documents, @readme.reload.folder

      patch tool_files_item_path(@tool, @readme), params: { folder_id: nil }, headers: @headers, as: :json

      assert_response :success
      assert_nil response.parsed_body["folder_id"]
      assert_nil @readme.reload.folder_id
    end

    test "update refuses to move a file into a folder of another tool" do
      other_folder = other_files_tool.file_folders.create!(name: "Elsewhere")

      patch tool_files_item_path(@tool, @readme), params: { folder_id: other_folder.id }, headers: @headers, as: :json

      assert_response :not_found
      assert_nil @readme.reload.folder_id
    end

    test "destroy deletes a file" do
      delete tool_files_item_path(@tool, @readme), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Files::Item.exists?(@readme.id)
    end

    test "uploading a single file returns it" do
      post tool_files_uploads_path(@tool), params: { file: uploaded_file("notes.txt", "hello"), folder_id: @documents.id }, headers: @headers

      assert_response :created
      files = response.parsed_body
      assert_equal 1, files.size
      assert_equal "notes.txt", files.first["name"]
      assert_equal 5, files.first["file_size"]
      assert_equal @documents.id, files.first["folder_id"]
      assert_equal @user.id, files.first.dig("creator", "id")
      assert_equal "hello", ::Files::Item.find(files.first["id"]).file.download
    end

    test "uploading several files returns them all and notifies collaborators once" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        post tool_files_uploads_path(@tool), params: { files: [ uploaded_file("one.txt", "1"), uploaded_file("two.txt", "22") ] }, headers: @headers
      end

      assert_response :created
      assert_equal [ "one.txt", "two.txt" ], response.parsed_body.map { |file| file["name"] }
      assert_equal [ nil, nil ], response.parsed_body.map { |file| file["folder_id"] }
    end

    test "uploading saves nothing when one of the files is refused" do
      assert_no_difference -> { ::Files::Item.count } do
        post tool_files_uploads_path(@tool), params: { files: [ uploaded_file("notes.txt", "fine"), uploaded_file("install.sh", "rm -rf") ] }, headers: @headers
      end

      assert_response :unprocessable_entity
      assert_equal [ "install.sh: File type .sh is not allowed for security reasons" ], response.parsed_body["errors"]
    end

    test "uploading without a file returns errors" do
      post tool_files_uploads_path(@tool), params: { folder_id: @documents.id }, headers: @headers

      assert_response :unprocessable_entity
      assert_equal [ "No file was uploaded" ], response.parsed_body["errors"]
    end

    test "download sends the file's bytes" do
      @readme.file.attach(io: StringIO.new("hello world"), filename: "readme.txt", content_type: "text/plain")

      get tool_files_item_download_path(@tool, @readme), headers: @headers

      assert_response :success
      assert_equal "hello world", response.body
      assert_match 'attachment; filename="readme.txt"', response.headers["Content-Disposition"]
    end

    test "folder download sends a zip of everything inside" do
      @report.file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
      nested_file = @tool.file_items.new(name: "notes.txt", folder: file_folders(:nested_folder))
      nested_file.file.attach(io: StringIO.new("nested notes"), filename: "notes.txt", content_type: "text/plain")
      nested_file.save!

      get tool_files_folder_download_path(@tool, @documents), headers: @headers

      assert_response :success
      assert_equal "application/zip", response.media_type
      entries = {}
      Zip::InputStream.open(StringIO.new(response.body)) do |zip|
        while (entry = zip.get_next_entry)
          entries[entry.name] = zip.read
        end
      end
      assert_equal({ "report.pdf" => "quarterly numbers", "Subfolder/notes.txt" => "nested notes" }, entries)
    end

    test "folders can be created, renamed and deleted with their contents" do
      subfolder = file_folders(:nested_folder)

      post tool_files_folders_path(@tool), params: { name: "Contracts", parent_id: @documents.id }, headers: @headers, as: :json

      assert_response :created
      folder_id = response.parsed_body["id"]
      assert_equal "Contracts", response.parsed_body["name"]
      assert_equal @documents.id, response.parsed_body["parent_id"]
      assert_equal tool_files_url(@tool, folder_id: folder_id), response.parsed_body["url"]

      patch tool_files_folder_path(@tool, folder_id), params: { name: "Legal" }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Legal", response.parsed_body["name"]

      delete tool_files_folder_path(@tool, @documents), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Files::Folder.exists?(folder_id)
      assert_not ::Files::Folder.exists?(subfolder.id)
      assert_not ::Files::Item.exists?(@report.id)
    end

    test "creating a folder in a folder of another tool is not found" do
      other_folder = other_files_tool.file_folders.create!(name: "Elsewhere")

      assert_no_difference -> { ::Files::Folder.count } do
        post tool_files_folders_path(@tool), params: { name: "Sneaky", parent_id: other_folder.id }, headers: @headers, as: :json
      end

      assert_response :not_found
    end

    test "creating a folder past the maximum depth returns errors" do
      parent = @tool.file_folders.create!(name: "Deep")
      parent.update_column(:depth, ::Files::Folder::MAX_DEPTH - 1)

      post tool_files_folders_path(@tool), params: { name: "Too deep", parent_id: parent.id }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Maximum folder depth of 10 reached"
    end

    test "update moves a folder into another folder and back to the top level" do
      photos = file_folders(:photos)

      patch tool_files_folder_path(@tool, photos), params: { parent_id: @documents.id }, headers: @headers, as: :json

      assert_response :success
      assert_equal @documents.id, response.parsed_body["parent_id"]
      assert_equal 1, photos.reload.depth

      patch tool_files_folder_path(@tool, photos), params: { parent_id: nil }, headers: @headers, as: :json

      assert_response :success
      assert_nil photos.reload.parent_id
      assert_equal 0, photos.depth
    end

    test "a folder can't be moved into itself or one of its subfolders" do
      [ @documents, file_folders(:nested_folder) ].each do |target|
        patch tool_files_folder_path(@tool, @documents), params: { parent_id: target.id }, headers: @headers, as: :json

        assert_response :unprocessable_entity
        assert_equal [ "A folder can't be moved into itself or one of its subfolders" ], response.parsed_body["errors"]
        assert_nil @documents.reload.parent_id
      end
    end

    test "a folder can't be moved into a folder of another tool" do
      other_folder = other_files_tool.file_folders.create!(name: "Elsewhere")

      patch tool_files_folder_path(@tool, @documents), params: { parent_id: other_folder.id }, headers: @headers, as: :json

      assert_response :not_found
      assert_nil @documents.reload.parent_id
    end

    test "a file's share link can be shown without exposing the password" do
      share = @report.create_share!(created_by: @user, expires_at: Time.zone.parse("2030-01-15"), password: "moonshot")

      get tool_files_item_share_path(@tool, @report), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal share_url(share.token), body["url"]
      assert_equal Time.zone.parse("2030-01-15"), Time.zone.parse(body["expires_at"])
      assert body["password_protected"]
      assert_equal 0, body["download_count"]
      assert_equal %w[url expires_at password_protected download_count created_at].sort, body.keys.sort
      assert_not_includes response.body, "moonshot"
      assert_not_includes response.body, share.password_digest
    end

    test "a file or folder without a share link has none to show" do
      get tool_files_item_share_path(@tool, @report), headers: @headers
      assert_response :not_found

      get tool_files_folder_share_path(@tool, @documents), headers: @headers
      assert_response :not_found
    end

    test "tokens can't create or remove public share links" do
      post tool_files_item_share_path(@tool, @report), params: { password: "moonshot" }, headers: @headers, as: :json
      assert_response :forbidden
      assert_nil @report.reload.share

      post tool_files_folder_share_path(@tool, @documents), headers: @headers, as: :json
      assert_response :forbidden
      assert_nil @documents.reload.share

      delete tool_files_item_share_path(@tool, @readme), headers: @headers, as: :json
      assert_response :forbidden
      assert_not_nil @readme.reload.share
    end

    test "read-only tokens can list and download but not change anything" do
      headers = api_headers(@user, permission: "read")
      @readme.file.attach(io: StringIO.new("hello world"), filename: "readme.txt", content_type: "text/plain")

      get tool_files_path(@tool), headers: headers
      assert_response :success

      get tool_files_item_download_path(@tool, @readme), headers: headers
      assert_response :success

      patch tool_files_item_path(@tool, @readme), params: { name: "Nope" }, headers: headers, as: :json
      assert_response :forbidden

      post tool_files_uploads_path(@tool), params: { file: uploaded_file("notes.txt", "hello") }, headers: headers
      assert_response :forbidden

      post tool_files_folders_path(@tool), params: { name: "Nope" }, headers: headers, as: :json
      assert_response :forbidden

      post tool_files_item_share_path(@tool, @report), headers: headers, as: :json
      assert_response :forbidden

      delete tool_files_folder_path(@tool, @documents), headers: headers, as: :json
      assert_response :forbidden

      assert_equal "readme.txt", @readme.reload.name
      assert_nil @report.reload.share
      assert ::Files::Folder.exists?(@documents.id)
    end

    test "files and folders are only reachable through their own tool" do
      other_tool = other_files_tool

      get tool_files_path(other_tool, folder_id: @documents.id), headers: @headers
      assert_response :not_found

      get tool_files_item_path(other_tool, @readme), headers: @headers
      assert_response :not_found

      get tool_files_item_download_path(other_tool, @readme), headers: @headers
      assert_response :not_found

      get tool_files_folder_download_path(other_tool, @documents), headers: @headers
      assert_response :not_found

      patch tool_files_folder_path(other_tool, @documents), params: { name: "Nope" }, headers: @headers, as: :json
      assert_response :not_found

      get tool_files_item_share_path(other_tool, @readme), headers: @headers
      assert_response :not_found

      post tool_files_uploads_path(other_tool), params: { file: uploaded_file("notes.txt", "hello"), folder_id: @documents.id }, headers: @headers
      assert_response :not_found

      assert_equal "Documents", @documents.reload.name
    end

    test "tools the user can't access are forbidden" do
      headers = api_headers(users(:two))

      get tool_files_path(@tool), headers: headers
      assert_response :forbidden

      get tool_files_item_path(@tool, @readme), headers: headers
      assert_response :forbidden

      get tool_files_item_download_path(@tool, @readme), headers: headers
      assert_response :forbidden

      get tool_files_item_share_path(@tool, @readme), headers: headers
      assert_response :forbidden
    end

    private

    def other_files_tool
      Tool.create!(name: "Other Files", tool_type: tool_types(:files), owner: @user)
    end

    def uploaded_file(name, content)
      Rack::Test::UploadedFile.new(StringIO.new(content), "text/plain", original_filename: name)
    end
  end
end
