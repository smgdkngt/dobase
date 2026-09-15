# frozen_string_literal: true

module Files
  # Files and folders picked together in a tool, as one zip: the files at the top,
  # and each folder under its own name with everything below it. The budget and
  # the walk through the folders are the same as a folder's.
  class SelectionArchive < FolderArchive
    def initialize(tool, folders:, files:)
      @tool = tool
      @folders = folders
      @picked_files = files
    end

    def filename
      "#{@tool.name}.zip"
    end

    private

    # Picked files outside the picked folders have no folder path, so they go at the top of the zip.
    def files
      super.or(Files::Item.joins(:file_blob).where(tool_id: tool_id, id: @picked_files))
    end

    def top_folder_paths
      @folders.to_h { |folder| [ folder.id, "#{folder.name}/" ] }
    end

    def tool_id
      @tool.id
    end
  end
end
