require "pathname"

class RoomFiles
  class NotFoundError < StandardError; end
  class BinaryFileError < StandardError; end

  def self.tree(room)
    build_tree_from_db(room)
  end

  def self.read(room, path)
    file = room.room_files.find_by(path: path, is_directory: false)
    raise NotFoundError unless file

    data = file.content || ""
    raise BinaryFileError if data.include?("\x00")

    data.force_encoding("UTF-8")
    data.valid_encoding? ? data : data.encode("UTF-8", invalid: :replace, undef: :replace)
  end

  def self.write(room, path, content)
    validate_path!(path)

    file = room.room_files.find_or_initialize_by(path: path)
    raise NotFoundError if file.persisted? && file.is_directory

    file.content = content
    file.is_directory = false
    file.save!
  end

  def self.resolve_path(room, relative_path)
    # Validate path to prevent directory traversal attacks
    path = relative_path.to_s
    raise NotFoundError if path.empty?
    raise NotFoundError if path.include?("..")
    raise NotFoundError if path.start_with?("/")

    path
  end

  def self.validate_path!(path)
    raise NotFoundError if path.to_s.empty?
    raise NotFoundError if path.include?("..")
    raise NotFoundError if path.start_with?("/")
  end

  def self.build_tree_from_db(room)
    files = room.room_files.order(:path)

    # Build a nested structure
    root = []
    dir_map = {}

    files.each do |file|
      parts = file.path.split("/")
      name = parts.last
      parent_path = parts[0..-2].join("/")

      entry = if file.is_directory
        { type: "dir", name: name, path: file.path, children: [] }
      else
        { type: "file", name: name, path: file.path }
      end

      if parent_path.empty?
        root << entry
        dir_map[file.path] = entry if file.is_directory
      else
        parent = dir_map[parent_path]
        if parent
          parent[:children] << entry
          dir_map[file.path] = entry if file.is_directory
        end
      end
    end

    root
  end
end
