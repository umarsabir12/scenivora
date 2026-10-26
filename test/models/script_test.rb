require "test_helper"

class ScriptTest < ActiveSupport::TestCase
  setup do
    @project = users(:one).projects.create!(prompt: "Why cats purr", tone: "casual", target_length_minutes: 3)
  end

  test "requires a body and a positive version" do
    script = @project.scripts.build(body: "", version: 0)

    assert_not script.valid?
    assert script.errors[:body].any?
    assert script.errors[:version].any?
  end

  test "version is unique within a project" do
    @project.scripts.create!(body: "Draft", version: 1)
    duplicate = @project.scripts.build(body: "Another", version: 1)

    assert_not duplicate.valid?
    assert duplicate.errors[:version].any?
  end

  test "different projects may share a version number" do
    other = users(:two).projects.create!(prompt: "Why dogs wag", tone: "casual", target_length_minutes: 3)
    @project.scripts.create!(body: "Draft", version: 1)

    assert other.scripts.build(body: "Draft", version: 1).valid?
  end

  test "word count counts whitespace-separated words" do
    script = @project.scripts.build(body: "One two  three\nfour", version: 1)

    assert_equal 4, script.word_count
  end
end
