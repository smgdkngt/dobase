# frozen_string_literal: true

module Mcp
  module Tools
    module Files
      extend Declaring

      def self.file
        { tool_id: tool_id("files"), file_id: id("The file's id", required: true) }
      end

      def self.folder
        { tool_id: tool_id("files"), folder_id: id("The folder's id", required: true) }
      end

      def self.file_path(call)
        "/tools/#{call.arg(:tool_id)}/files/items/#{call.arg(:file_id)}"
      end

      def self.folder_path(call)
        "/tools/#{call.arg(:tool_id)}/files/folders/#{call.arg(:folder_id)}"
      end

      tool "file_list", "List a folder", "The folders and files at the top of a files tool, or in one folder.",
        params: { tool_id: tool_id("files"), folder_id: id("The folder to list instead of the top") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/files", folder_id: arg(:folder_id)
      end

      tool "file_show", "Show a file", "A file's name, size, type, folder and links.", params: file, read_only: true do
        get Files.file_path(self)
      end

      tool "file_read", "Read a file",
        "What can be read out of a file without downloading it: the text of a text, markdown or code file, the rows " \
        "of a csv or spreadsheet, the paragraphs of a Word document. Works for a file in a files tool and for an " \
        "attachment of a mail, card, todo or chat message: pass its preview id (the id in its preview_url) and the " \
        "tool it hangs in. Pictures, pdfs, sound and video have nothing to read here.",
        params: {
          tool_id: id("The tool the file or attachment is in", required: true),
          preview_id: id("The id in the file's preview_url", required: true)
        }, read_only: true do
        get "/tools/#{arg(:tool_id)}/file_previews/#{arg(:preview_id)}"
      end

      tool "folder_share", "A folder's share link", "A folder's public share link, or nothing when it has none.",
        params: folder, read_only: true do
        get Files.folder_path(self) + "/share"
      rescue Api::Error => error
        raise unless error.status == 404
      end

      tool "file_upload", "Upload files", "Adds files to a files tool, at the top or in a folder.",
        params: { tool_id: tool_id("files"), folder_id: id("The folder to put them in"), files: file_list("The files", required: true) } do
        upload "/tools/#{arg(:tool_id)}/files/uploads", { files: files(:files), folder_id: arg(:folder_id) }.compact
      end

      tool "file_rename", "Rename a file", "Renames a file.", params: file.merge(name: text("Its new name", required: true)) do
        patch Files.file_path(self), name: arg(:name)
      end

      tool "file_move", "Move a file", "Moves a file into a folder, or to the top without one.",
        params: file.merge(to_folder_id: id("The folder to move it into (leave out for the top)")) do
        patch Files.file_path(self), folder_id: arg(:to_folder_id)
      end

      tool "file_delete", "Delete a file", "Deletes a file for good.", params: file, destructive: true do
        delete Files.file_path(self)
      end

      tool "folder_create", "Add a folder", "Adds a folder, at the top or inside another.",
        params: { tool_id: tool_id("files"), name: text("Its name", required: true), parent_id: id("The folder to put it in") } do
        post "/tools/#{arg(:tool_id)}/files/folders", args(:name, :parent_id)
      end

      tool "folder_rename", "Rename a folder", "Renames a folder.", params: folder.merge(name: text("Its new name", required: true)) do
        patch Files.folder_path(self), name: arg(:name)
      end

      tool "folder_move", "Move a folder", "Moves a folder into another, or to the top without one.",
        params: folder.merge(to_folder_id: id("The folder to move it into (leave out for the top)")) do
        patch Files.folder_path(self), parent_id: arg(:to_folder_id)
      end

      tool "folder_delete", "Delete a folder", "Deletes a folder with everything in it, for good.",
        params: folder, destructive: true do
        delete Files.folder_path(self)
      end
    end
  end
end
