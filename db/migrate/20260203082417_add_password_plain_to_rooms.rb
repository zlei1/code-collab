class AddPasswordPlainToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :password_plain, :string
  end
end
