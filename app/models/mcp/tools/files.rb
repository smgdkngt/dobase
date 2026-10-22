# frozen_string_literal: true

module Mcp
  module Tools
    module Files
      extend Declaring

      tool "file_list", "List a folder", "The folders and files at the top of a files tool, or in one folder.",
        params: { tool_id: tool_id("files"), folder_id: id("The folder to list instead of the top") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/files", folder_id: arg(:folder_id)
      end

      tool "file_show", "Show a file", "A file's name, size, type, folder and links.",
        params: { tool_id: tool_id("files"), file_id: id("The file's id", required: true) }, read_only: true do
        get "/tools/#{arg(:tool_id)}/files/items/#{arg(:file_id)}"
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
    end
  end
end
