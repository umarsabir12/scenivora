require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes the email address" do
    user = User.new(email: "  Creator@Example.COM ", password: "password123")

    assert_equal "creator@example.com", user.email
  end

  test "requires a valid, unique email address" do
    assert_not User.new(email: "not-an-email", password: "password123").valid?
    assert_not User.new(email: users(:one).email, password: "password123").valid?
  end

  test "requires passwords of at least 8 characters" do
    user = User.new(email: "new@example.com", password: "short")

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "credits balance defaults to zero and cannot be negative" do
    user = User.create!(email: "credits@example.com", password: "password123")

    assert_equal 0, user.credits_balance
    user.credits_balance = -1
    assert_not user.valid?
  end

  test "destroying a user destroys their projects" do
    user = users(:one)
    user.projects.create!(prompt: "A story about bees", tone: "casual", target_length_minutes: 3)

    assert_difference -> { Project.count }, -1 do
      user.destroy!
    end
  end
end
