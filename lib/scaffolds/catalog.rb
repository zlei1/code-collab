require "yaml"

module Scaffolds
  class Catalog
    def self.all
      @all ||= load_catalog
    end

    def self.find(key)
      all.find { |entry| entry["key"] == key }
    end

    def self.load_catalog
      path = Rails.root.join("lib", "scaffolds", "scaffolds.yml")
      YAML.load_file(path)
    end
  end
end
