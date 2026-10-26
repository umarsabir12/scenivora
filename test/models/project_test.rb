require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @project = users(:one).projects.create!(
      prompt: "How the Roman aqueducts still shape modern cities",
      tone: "documentary",
      target_length_minutes: 5
    )
  end

  test "defaults the title from the prompt when none is given" do
    assert_equal "How the Roman aqueducts still shape modern cities", @project.title
  end

  test "starts as a draft" do
    assert @project.draft?
  end

  test "requires a prompt, a known tone, and a target length between 3 and 10 minutes" do
    project = users(:one).projects.build(prompt: "", tone: "silly", target_length_minutes: 11)

    assert_not project.valid?
    assert project.errors[:prompt].any?
    assert project.errors[:tone].any?
    assert project.errors[:target_length_minutes].any?
  end

  test "rejects target lengths below 3 minutes" do
    @project.target_length_minutes = 2

    assert_not @project.valid?
  end

  test "status only accepts the defined pipeline states" do
    assert_equal %w[draft script_ready voice_ready scenes_ready media_ready rendering rendered],
      Project.statuses.keys
    @project.status = "published"

    assert_not @project.valid?
  end

  test "target word count is about 150 words per minute" do
    assert_equal 750, @project.target_word_count
  end

  test "latest script is the highest version and next version increments" do
    assert_nil @project.latest_script
    assert_equal 1, @project.next_script_version

    @project.scripts.create!(body: "First draft", version: 1)
    @project.scripts.create!(body: "Second draft", version: 2)

    assert_equal 2, @project.latest_script.version
    assert_equal 3, @project.next_script_version
  end

  test "reads the script generating flag from settings" do
    assert_not @project.script_generating?

    @project.update!(settings: { "script_generating" => true })

    assert @project.script_generating?
  end

  test "destroying a project destroys its scripts and usage" do
    @project.scripts.create!(body: "Narration", version: 1)
    @project.api_usages.create!(provider: "openai", operation: "script", units: 10, cost_usd: 0)

    assert_difference "Script.count", -1 do
      assert_difference "ApiUsage.count", -1 do
        @project.destroy!
      end
    end
  end
end
