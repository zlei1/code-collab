require "fileutils"

class RoomWorkspace
  def self.ensure!(room)
    root = root_path(room)
    return if Dir.exist?(root)

    template = Scaffolds::Catalog.find(room.template_key)
    raise "Unknown scaffold" unless template

    source = Rails.root.join("lib", "scaffolds", template["key"]).to_s
    FileUtils.mkdir_p(root)
    FileUtils.cp_r("#{source}/.", root)
  end

  def self.root_path(room)
    room.workspace_path.to_s
  end
end
