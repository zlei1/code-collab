class Room < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :room_memberships, dependent: :destroy
  has_many :users, through: :room_memberships
  has_many :room_messages, dependent: :destroy
  has_many :room_runs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :template_key, presence: true

  before_validation :ensure_slug, on: :create
  validate :template_key_exists

  def ensure_slug
    return if slug.present?
    self.slug = loop do
      candidate = SecureRandom.alphanumeric(8).downcase
      break candidate unless self.class.exists?(slug: candidate)
    end
  end

  def workspace_path
    Rails.root.join("storage", "rooms", id.to_s)
  end

  def template_key_exists
    return if Scaffolds::Catalog.find(template_key)
    errors.add(:template_key, "is not supported")
  end
end
