class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  has_many :projects, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :credits_balance, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
