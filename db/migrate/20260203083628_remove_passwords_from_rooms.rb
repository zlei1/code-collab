class RemovePasswordsFromRooms < ActiveRecord::Migration[8.1]
  def change
    remove_column :rooms, :password_digest, :string
    remove_column :rooms, :password_plain, :string
  end
end
