class RoomRun < ApplicationRecord
  belongs_to :room
  belongs_to :user

  STATUSES = %w[queued running succeeded failed].freeze

  validates :status, inclusion: { in: STATUSES }
end
