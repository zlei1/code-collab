require "pathname"
require "fileutils"

class RoomFiles
  class NotFoundError < StandardError; end
  class BinaryFileError < StandardError; end

  def self.tree(room)
    root = RoomWorkspace.root_path(room)
    build_tree(root, root)
  end

  def self.read(room, path)
    full_path = resolve_path(room, path)
    raise NotFoundError unless File.file?(full_path)

    data = File.binread(full_path)
    raise BinaryFileError if data.include?("\x00")

    data.force_encoding("UTF-8")
    data.valid_encoding? ? data : data.encode("UTF-8", invalid: :replace, undef: :replace)
  end

  def self.write(room, path, content)
    full_path = resolve_path(room, path)
    raise NotFoundError if File.directory?(full_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def self.resolve_path(room, relative_path)
    root = Pathname.new(RoomWorkspace.root_path(room))
    candidate = root.join(relative_path.to_s).cleanpath
    root_prefix = root.to_s.end_with?(File::SEPARATOR) ? root.to_s : "#{root}#{File::SEPARATOR}"
    raise NotFoundError unless candidate.to_s == root.to_s || candidate.to_s.start_with?(root_prefix)

    candidate.to_s
  end

  def self.build_tree(root, current)
    entries = Dir.children(current).sort.map do |name|
      next if name.start_with?(".")
      next if %w[node_modules log tmp].include?(name)

      path = File.join(current, name)
      rel = path.delete_prefix("#{root}/")
      if File.directory?(path)
        { type: "dir", name: name, path: rel, children: build_tree(root, path) }
      else
        { type: "file", name: name, path: rel }
      end
    end
    entries.compact
  end
end
