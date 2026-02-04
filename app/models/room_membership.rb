class RoomMembership < ApplicationRecord
  belongs_to :room
  belongs_to :user

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :room_id }
end
