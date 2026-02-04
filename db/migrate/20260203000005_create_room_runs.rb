class CreateRoomRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :room_runs do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.text :stdout
      t.text :stderr
      t.integer :exit_code
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
  end
end
