# frozen_string_literal: true

module Dobase
  module Commands
    class Files < Command
      DOWNLOAD_FLAGS = {
        output: [ "PATH", "Save to PATH, or into PATH when it is a directory" ],
        force: [ nil, "Overwrite an existing file" ]
      }.freeze
      noun "file", "Files and their downloads (files tools)"
      noun "folder", "Folders of files (files tools)"

      command "file list", "List the folders and files at the top level, or in FOLDER (a folder id)", args: %w[TOOL [FOLDER]] do |ref, folder = nil|
        files_tool = tool(ref, "files")
        listing = get("/tools/#{files_tool["id"]}/files", folder_id: folder && folder_id(folder))

        output(listing) do
          trail = [ files_tool["name"], *listing["breadcrumbs"].map { |crumb| crumb["name"] }, listing.dig("folder", "name") ].compact
          location = listing["folder"] ? "folder #{files_tool["id"]}/#{listing["folder"]["id"]}" : "files #{files_tool["id"]}"
          say "#{trail.join(" / ")} (#{location}) #{listing["url"]}"
          say

          rows = listing["folders"].map { |entry| [ "folder #{files_tool["id"]}/#{entry["id"]}", entry["name"], "", "", ("shared" if entry["shared"]) ] } +
            listing["files"].map { |entry| [ "#{files_tool["id"]}/#{entry["id"]}", entry["name"], bytes(entry["file_size"]), day(entry["created_at"]), ("shared" if entry["shared"]) ] }
          rows.empty? ? say("  (empty)") : table(rows)
        end
      end

      command "file show", "Show a file's details and its public link, if it has one", args: %w[TOOL/FILE] do |ref|
        files_tool, id = tool_and_id(ref, "files", "file")
        file = get("/tools/#{files_tool["id"]}/files/items/#{id}")

        output(file) do
          say "#{file["name"]} (file #{files_tool["id"]}/#{file["id"]})"
          field "Folder", file["folder_id"] ? "folder #{files_tool["id"]}/#{file["folder_id"]}" : "top level"
          field "Type", file["content_type"]
          field "Size", bytes(file["file_size"])
          field "Created", [ moment(file["created_at"]), file.dig("creator", "name") ].compact.join(" by ")
          field "URL", file["url"]
          field "Download", file["download_url"]
          field "Shared", share_summary(file["share"]) if file["share"]
        end
      end

      command "file upload", "Upload files (200 MB max each), to the top level unless --folder", args: %w[TOOL PATH...],
        flags: { folder: [ "FOLDER", "Folder id to upload into" ] } do |ref, *paths, folder: nil|
        files_tool = tool(ref, "files")
        paths.each { |path| raise Error, "#{path} is not a file." unless File.file?(path) }

        uploaded = client.upload("/tools/#{files_tool["id"]}/files/uploads", files: { "files[]" => paths }, fields: { folder_id: folder && folder_id(folder) })
        output(uploaded) do
          uploaded.each { |file| say "Uploaded #{file["name"]} (#{bytes(file["file_size"])}) to #{place(files_tool, file["folder_id"])} as #{files_tool["id"]}/#{file["id"]}." }
        end
      end

      command "file download", "Download a file, to its own name in the current directory unless --output", args: %w[TOOL/FILE],
        flags: DOWNLOAD_FLAGS do |ref, **options|
        files_tool, id = tool_and_id(ref, "files", "file")
        file = get("/tools/#{files_tool["id"]}/files/items/#{id}")

        path = download("/tools/#{files_tool["id"]}/files/items/#{id}/download", name: file["name"], **options)
        output(file.merge("path" => path)) { say "Downloaded #{file["name"]} (#{bytes(file["file_size"])}) to #{path}." }
      end

      command "file rename", "Rename a file", args: %w[TOOL/FILE NAME] do |ref, name|
        files_tool, id = tool_and_id(ref, "files", "file")
        file = patch("/tools/#{files_tool["id"]}/files/items/#{id}", name: name)
        output(file) { say "Renamed file #{files_tool["id"]}/#{file["id"]} to #{quoted(file["name"])}." }
      end

      command "file move", "Move a file into FOLDER (a folder id), or to the top level with root", args: %w[TOOL/FILE FOLDER] do |ref, folder|
        files_tool, id = tool_and_id(ref, "files", "file")
        file = patch("/tools/#{files_tool["id"]}/files/items/#{id}", folder_id: folder_id(folder))
        output(file) { say "Moved file #{files_tool["id"]}/#{file["id"]} #{quoted(file["name"])} to #{place(files_tool, file["folder_id"])}." }
      end

      command "file delete", "Delete a file permanently", args: %w[TOOL/FILE] do |ref|
        files_tool, id = tool_and_id(ref, "files", "file")
        delete("/tools/#{files_tool["id"]}/files/items/#{id}")
        output(nil) { say "Deleted file #{files_tool["id"]}/#{id}." }
      end

      command "folder create", "Create a folder, at the top level unless --parent", args: %w[TOOL NAME],
        flags: { parent: [ "FOLDER", "Folder id to create it in" ] } do |ref, name, parent: nil|
        files_tool = tool(ref, "files")
        folder = post("/tools/#{files_tool["id"]}/files/folders", { name: name, parent_id: parent && folder_id(parent) }.compact)
        location = folder["parent_id"] ? "in #{place(files_tool, folder["parent_id"])}" : "at the top level"
        output(folder) { say "Created folder #{files_tool["id"]}/#{folder["id"]} #{quoted(folder["name"])} #{location}: #{folder["url"]}" }
      end

      command "folder rename", "Rename a folder", args: %w[TOOL/FOLDER NAME] do |ref, name|
        files_tool, id = tool_and_id(ref, "files", "folder")
        folder = patch("/tools/#{files_tool["id"]}/files/folders/#{id}", name: name)
        output(folder) { say "Renamed folder #{files_tool["id"]}/#{folder["id"]} to #{quoted(folder["name"])}." }
      end

      command "folder move", "Move a folder into PARENT (a folder id), or to the top level with root", args: %w[TOOL/FOLDER PARENT] do |ref, parent|
        files_tool, id = tool_and_id(ref, "files", "folder")
        folder = patch("/tools/#{files_tool["id"]}/files/folders/#{id}", parent_id: folder_id(parent))
        output(folder) { say "Moved folder #{files_tool["id"]}/#{folder["id"]} #{quoted(folder["name"])} to #{place(files_tool, folder["parent_id"])}." }
      end

      command "folder delete", "Delete a folder and everything in it, permanently", args: %w[TOOL/FOLDER] do |ref|
        files_tool, id = tool_and_id(ref, "files", "folder")
        delete("/tools/#{files_tool["id"]}/files/folders/#{id}")
        output(nil) { say "Deleted folder #{files_tool["id"]}/#{id} and everything in it." }
      end

      command "folder download", "Download a folder and everything in it as a zip, to FOLDER-NAME.zip unless --output", args: %w[TOOL/FOLDER],
        flags: DOWNLOAD_FLAGS do |ref, **options|
        files_tool, id = tool_and_id(ref, "files", "folder")
        folder = get("/tools/#{files_tool["id"]}/files", folder_id: id)["folder"]

        path = download("/tools/#{files_tool["id"]}/files/folders/#{id}/download", name: "#{folder["name"]}.zip", **options)
        output(folder.merge("path" => path)) { say "Downloaded folder #{files_tool["id"]}/#{id} #{quoted(folder["name"])} to #{path}." }
      end

      private

      # A folder id (TOOL/ID works too), or nil for root: the top level.
      def folder_id(value)
        return nil if value == "root"

        id = value.to_s.split("/").last.to_s
        raise UsageError, "Expected a folder id like 12, or root; got #{quoted(value)}." unless id.match?(/\A\d+\z/)

        id.to_i
      end

      def place(files_tool, folder_id)
        folder_id ? "folder #{files_tool["id"]}/#{folder_id}" : "the top level"
      end

      # Saves a download into the current directory under `name` (only its last
      # path segment, whatever the server sent), or to --output. Returns the path.
      def download(path, name:, output: nil, force: false)
        name = File.basename(name.to_s)
        name = "download" if name.delete("./").empty?
        destination = output.nil? ? name : (File.directory?(output) ? File.join(output, name) : output)

        raise Error, "#{File.dirname(destination)} is not a directory." unless File.directory?(File.dirname(destination))
        raise Error, "#{destination} already exists. Use --force to overwrite it." if File.exist?(destination) && !force

        client.download(path, destination)
        destination
      end

      def share_summary(share)
        details = [
          ("expires #{day(share["expires_at"])}" if share["expires_at"]),
          ("password protected" if share["password_protected"]),
          "downloaded #{count(share["download_count"], "time")}"
        ].compact
        "#{share["url"]} (#{details.join(", ")})"
      end
    end
  end
end
