# frozen_string_literal: true

module Files
  # A zip of every file below a folder. Share links make folder downloads public,
  # so an archive has a size and file count budget and is written to disk a chunk
  # at a time instead of being built in memory. Files are stored as they are:
  # photos, video, PDFs and Office documents are compressed already, and deflating
  # them again would cost a lot of CPU for little gain.
  class FolderArchive
    MAX_BYTES = 1.gigabyte
    MAX_FILES = 1_000

    attr_reader :folder

    def initialize(folder)
      @folder = folder
    end

    def filename
      "#{folder.name}.zip"
    end

    def too_large?
      files.count > MAX_FILES || files.sum("active_storage_blobs.byte_size") > MAX_BYTES
    end

    # Writes the zip to the file at path. rubyzip seeks back to finish each
    # entry, so it can't write to the response directly.
    def write(path)
      require "zip"

      taken = Set.new
      Zip::OutputStream.open(path) do |zip|
        files.with_attached_file.find_each do |item|
          name = unique_name("#{folder_paths[item.folder_id]}#{path_segment(item.name)}", taken)
          zip.put_next_entry(name, nil, nil, Zip::Entry::STORED)
          item.file.download { |chunk| zip << chunk }
        end
      end
    end

    private

    def files
      Files::Item.joins(:file_blob).where(tool_id: tool_id, folder_id: folder_paths.keys)
    end

    # Where each folder of the tree goes inside the zip, by folder id. Takes one
    # query per level and skips folders it has already seen, so a tree that loops
    # back on itself still ends.
    def folder_paths
      @folder_paths ||= top_folder_paths.tap do |paths|
        parent_ids = paths.keys

        while parent_ids.any?
          children = Files::Folder.where(tool_id: tool_id, parent_id: parent_ids).where.not(id: paths.keys).pluck(:id, :parent_id, :name)
          children.each { |id, parent_id, name| paths[id] = "#{paths[parent_id]}#{path_segment(name)}/" }
          parent_ids = children.map(&:first)
        end
      end
    end

    # The folders the walk starts from, by id, with their place in the zip.
    def top_folder_paths
      { folder.id => "" }
    end

    def tool_id
      folder.tool_id
    end

    # A file or folder name as one path segment. Names come from users, and a "/", "\"
    # or ".." in them would make the zip unpack outside the folder it's unpacked into.
    def path_segment(name)
      segment = name.to_s.gsub(%r{[/\\]}, "-").gsub(/[[:cntrl:]]/, "").strip
      segment.empty? || segment.in?(%w[. ..]) ? "_" : segment
    end

    # Two files with the same name would unpack onto each other, so later ones get
    # numbered the way file managers do. Case-insensitive, like macOS and Windows.
    def unique_name(name, taken)
      candidate = name
      number = 1
      while taken.include?(candidate.downcase)
        number += 1
        candidate = name.sub(/(\.[^.\/]+)?\z/) { " (#{number})#{$1}" }
      end
      taken << candidate.downcase
      candidate
    end
  end
end
