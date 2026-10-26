class CreditTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :project, optional: true

  validates :amount, numericality: { only_integer: true, other_than: 0 }
  validates :balance_after, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reason, presence: true
end
