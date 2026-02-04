require "fileutils"

class RoomWorkspace
  def self.ensure!(room)
    # No longer needed to copy to filesystem here as files are in DB
    # But we can check if template files are in DB
    return if room.room_files.exists?

    template = Scaffolds::Catalog.find(room.template_key)
    raise "Unknown scaffold" unless template

    source = Rails.root.join("lib", "scaffolds", template["key"]).to_s
    load_template_files(room, source, "")
  end

  def self.root_path(room)
    Rails.root.join("tmp", "workspaces", room.id.to_s)
  end

  def self.export_to_disk(room)
    root = root_path(room)
    FileUtils.mkdir_p(root)

    room.room_files.each do |file|
      path = File.join(root, file.path)
      if file.is_directory?
        FileUtils.mkdir_p(path)
      else
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, file.content || "")
      end
    end
  end

  def self.cleanup(room)
    root = root_path(room)
    FileUtils.rm_rf(root)
  end

  private

  def self.load_template_files(room, source_dir, relative_path)
    Dir.foreach(source_dir) do |entry|
      next if entry.start_with?(".")

      full_path = File.join(source_dir, entry)
      file_relative_path = relative_path.empty? ? entry : File.join(relative_path, entry)

      if File.directory?(full_path)
        # Create directory entry
        room.room_files.create!(
          path: file_relative_path,
          is_directory: true,
          content: nil
        )
        # Recursively load subdirectory
        load_template_files(room, full_path, file_relative_path)
      else
        # Create file entry
        content = File.read(full_path)
        room.room_files.create!(
          path: file_relative_path,
          is_directory: false,
          content: content
        )
      end
    end
  end
end
