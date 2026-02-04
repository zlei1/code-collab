class RoomFile < ApplicationRecord
  belongs_to :room

  validates :path, presence: true
  validates :path, uniqueness: { scope: :room_id }
  validates :room_id, presence: true

  scope :files, -> { where(is_directory: false) }
  scope :directories, -> { where(is_directory: true) }

  def directory?
    is_directory
  end

  def file?
    !is_directory
  end
end
