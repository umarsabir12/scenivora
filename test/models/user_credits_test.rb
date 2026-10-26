require "test_helper"

class UserCreditsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How tides work", tone: "documentary", target_length_minutes: 3)
  end

  test "granting adds credits and records the change" do
    @user.grant_credits!(20, reason: "manual_grant")

    assert_equal 20, @user.reload.credits_balance
    entry = @user.credit_transactions.last
    assert_equal 20, entry.amount
    assert_equal 20, entry.balance_after
    assert_equal "manual_grant", entry.reason
  end

  test "charging takes credits and records a negative change against the project" do
    @user.grant_credits!(10, reason: "manual_grant")

    @user.charge_credits!(4, reason: "ai_image", project: @project)

    assert_equal 6, @user.reload.credits_balance
    entry = @user.credit_transactions.order(:id).last
    assert_equal(-4, entry.amount)
    assert_equal 6, entry.balance_after
    assert_equal @project, entry.project
  end

  test "charging more than the balance is refused and changes nothing" do
    @user.grant_credits!(3, reason: "manual_grant")

    assert_raises(User::InsufficientCredits) { @user.charge_credits!(5, reason: "ai_image") }

    assert_equal 3, @user.reload.credits_balance
    assert_equal 1, @user.credit_transactions.count
  end

  test "deleting a project keeps its credit history" do
    @user.grant_credits!(5, reason: "manual_grant")
    @user.charge_credits!(5, reason: "ai_image", project: @project)

    @project.destroy!

    assert_equal 2, @user.credit_transactions.count
    assert_nil @user.credit_transactions.order(:id).last.project
  end
end
