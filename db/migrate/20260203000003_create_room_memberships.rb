class CreateRoomMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :room_memberships do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :room_memberships, [:room_id, :user_id], unique: true
  end
end
