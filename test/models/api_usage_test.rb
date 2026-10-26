require "test_helper"

class ApiUsageTest < ActiveSupport::TestCase
  setup do
    @project = users(:one).projects.create!(prompt: "Why the sky is blue", tone: "casual", target_length_minutes: 3)
  end

  test "is valid with provider, operation, units and cost" do
    usage = @project.api_usages.build(provider: "openai", operation: "script", units: 1200, cost_usd: 0.00042)

    assert usage.valid?
  end

  test "requires provider and operation" do
    usage = @project.api_usages.build(units: 0, cost_usd: 0)

    assert_not usage.valid?
    assert usage.errors[:provider].any?
    assert usage.errors[:operation].any?
  end

  test "units and cost cannot be negative" do
    usage = @project.api_usages.build(provider: "openai", operation: "script", units: -1, cost_usd: -0.01)

    assert_not usage.valid?
    assert usage.errors[:units].any?
    assert usage.errors[:cost_usd].any?
  end
end
