class RoomMessage < ApplicationRecord
  belongs_to :room
  belongs_to :user

  validates :content, presence: true
end
