class CreateRoomFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :room_files do |t|
      t.references :room, null: false, foreign_key: true
      t.string :path, null: false
      t.text :content
      t.boolean :is_directory, null: false, default: false

      t.timestamps
    end

    add_index :room_files, [ :room_id, :path ], unique: true
  end
end
