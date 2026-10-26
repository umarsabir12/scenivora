class ApiUsage < ApplicationRecord
  belongs_to :project

  validates :provider, :operation, presence: true
  validates :units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }
end
