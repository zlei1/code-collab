class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :password_digest, null: false
      t.string :template_key, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :rooms, :slug, unique: true
  end
end
