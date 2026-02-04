class CreateRoomMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :room_messages do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end
  end
end
