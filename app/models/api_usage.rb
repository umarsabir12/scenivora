class ApiUsage < ApplicationRecord
  # A cost belongs to a YouTube project or to a single-tool creation.
  belongs_to :project, optional: true
  belongs_to :creation, optional: true

  validates :provider, :operation, presence: true
  validate :has_owner
  validates :units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  private
    def has_owner
      errors.add(:base, "A cost needs a project or a creation") unless project || creation
    end
end
