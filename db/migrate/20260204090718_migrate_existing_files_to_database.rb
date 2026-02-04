class MigrateExistingFilesToDatabase < ActiveRecord::Migration[8.1]
  def up
    storage_path = Rails.root.join("storage", "rooms")
    return unless Dir.exist?(storage_path)

    migrated_count = 0
    Room.find_each do |room|
      room_dir = storage_path.join(room.id.to_s)
      next unless Dir.exist?(room_dir)

      puts "Migrating files for room #{room.id} (#{room.name})..."

      migrate_directory(room, room_dir, "")
      migrated_count += 1
    end

    puts "Migration complete. Migrated files for #{migrated_count} rooms."
  end

  def down
    # Restore files from database to filesystem
    RoomFile.find_each do |room_file|
      room = room_file.room
      storage_path = Rails.root.join("storage", "rooms", room.id.to_s)
      file_path = storage_path.join(room_file.path)

      if room_file.is_directory
        FileUtils.mkdir_p(file_path)
      else
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, room_file.content || "")
      end
    end

    puts "Restored files to filesystem."
  end

  private

  def migrate_directory(room, dir_path, relative_path)
    Dir.foreach(dir_path) do |entry|
      next if entry.start_with?(".")
      next if %w[node_modules log tmp].include?(entry)

      full_path = dir_path.join(entry)
      file_relative_path = relative_path.empty? ? entry : File.join(relative_path, entry)

      if File.directory?(full_path)
        # Create directory entry
        RoomFile.create!(
          room: room,
          path: file_relative_path,
          is_directory: true,
          content: nil
        )
        # Recursively migrate subdirectory
        migrate_directory(room, full_path, file_relative_path)
      else
        # Create file entry
        content = File.binread(full_path)
        # Skip binary files
        next if content.include?("\x00")

        content.force_encoding("UTF-8")
        content = content.valid_encoding? ? content : content.encode("UTF-8", invalid: :replace, undef: :replace)

        RoomFile.create!(
          room: room,
          path: file_relative_path,
          is_directory: false,
          content: content
        )
      end
    end
  rescue => e
    puts "Error migrating directory #{dir_path}: #{e.message}"
  end
end
