class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  class InsufficientCredits < StandardError; end

  has_many :projects, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :credits_balance, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Takes credits for a paid action. Locks the user row so two requests can't spend the same credits.
  def charge_credits!(amount, reason:, project: nil)
    with_lock do
      raise InsufficientCredits, "Needs #{amount} credits, has #{credits_balance}" if credits_balance < amount

      change_credits!(-amount, reason: reason, project: project)
    end
  end

  # Adds credits: a grant, or a refund after a failed paid action.
  def grant_credits!(amount, reason:, project: nil)
    with_lock { change_credits!(amount, reason: reason, project: project) }
  end

  private
    def change_credits!(amount, reason:, project:)
      update!(credits_balance: credits_balance + amount)
      credit_transactions.create!(amount: amount, balance_after: credits_balance, reason: reason, project: project)
    end
end
