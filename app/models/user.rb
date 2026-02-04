class User < ApplicationRecord
  has_secure_password

  has_many :owned_rooms, class_name: "Room", foreign_key: :owner_id, dependent: :destroy
  has_many :room_memberships, dependent: :destroy
  has_many :rooms, through: :room_memberships
  has_many :room_messages, dependent: :destroy
  has_many :room_runs, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.downcase.strip
  end
end
