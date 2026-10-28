require "test_helper"

class GenerateMetadataJobTest < ActiveJob::TestCase
  class FakeMetadata
    def initialize(error: nil)
      @error = error
    end

    def call(topic:, tone:, script:)
      raise @error if @error

      Ai::MetadataGenerator::Result.new(title: "Why the Sea Rises", description: "A hook about tides.",
        tags: %w[tides moon], category: "Education", total_tokens: 800, cost_usd: BigDecimal("0.0003"))
    end
  end

  setup do
    @project = project_with_approved_scenes(status: "rendered")
    @project.update!(settings: @project.settings.merge("metadata_generating" => true))
  end

  test "saves the details with the credits footer and records the cost" do
    with_stubbed_new(Ai::MetadataGenerator, FakeMetadata.new) { GenerateMetadataJob.perform_now(@project) }

    @project.reload
    assert_equal "Why the Sea Rises", @project.yt_title
    assert @project.yt_description.start_with?("A hook about tides.\n\nNarration is AI-generated.")
    assert_equal %w[tides moon], @project.yt_tags
    assert_equal "Education", @project.yt_category
    assert_nil @project.settings["metadata_generating"]
    assert_equal 800, @project.api_usages.find_by(operation: "metadata").units
  end

  test "a failure keeps earlier details and shows the reason" do
    @project.update!(yt_title: "Old title")

    with_stubbed_new(Ai::MetadataGenerator, FakeMetadata.new(error: Ai::Error.new("Text generation failed: quota"))) do
      GenerateMetadataJob.perform_now(@project)
    end

    @project.reload
    assert_equal "Old title", @project.yt_title
    assert_equal "Text generation failed: quota", @project.settings["metadata_error"]
    assert_nil @project.settings["metadata_generating"]
  end
end
