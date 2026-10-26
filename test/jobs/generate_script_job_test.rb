require "test_helper"

class GenerateScriptJobTest < ActiveJob::TestCase
  # Stands in for Ai::TextGenerator so no test calls the real provider.
  FakeGenerator = Struct.new(:result, :error) do
    attr_reader :received

    def call(system_prompt:, user_prompt:, **)
      @received = { system_prompt: system_prompt, user_prompt: user_prompt }
      raise error if error

      result
    end
  end

  setup do
    @project = users(:one).projects.create!(
      prompt: "The hidden engineering of suspension bridges",
      tone: "dramatic",
      target_length_minutes: 4
    )
    @project.update!(settings: { "script_generating" => true })
  end

  def generation_result(text: "A gripping hook.\n\nThe turning point.", total_tokens: 1_200, cost_usd: BigDecimal("0.00032"))
    Ai::TextGenerator::Result.new(
      text: text, provider: "openai", model: "gpt-4o-mini", total_tokens: total_tokens, cost_usd: cost_usd
    )
  end

  def perform_with(generator)
    original_new = Ai::TextGenerator.method(:new)
    Ai::TextGenerator.define_singleton_method(:new) { |*| generator }
    GenerateScriptJob.perform_now(@project)
  ensure
    Ai::TextGenerator.define_singleton_method(:new, original_new)
  end

  test "saves the script as version 1 and marks the project script_ready" do
    perform_with(FakeGenerator.new(generation_result))

    script = @project.reload.latest_script
    assert_equal 1, script.version
    assert_equal "A gripping hook.\n\nThe turning point.", script.body
    assert @project.script_ready?
  end

  test "records token usage and estimated cost against the project" do
    perform_with(FakeGenerator.new(generation_result(total_tokens: 1_200, cost_usd: BigDecimal("0.00032"))))

    usage = @project.api_usages.sole
    assert_equal "openai", usage.provider
    assert_equal "script", usage.operation
    assert_equal 1_200, usage.units
    assert_equal BigDecimal("0.00032"), usage.cost_usd
  end

  test "asks for a narration prompt that carries the brief, tone and target length" do
    generator = FakeGenerator.new(generation_result)
    perform_with(generator)

    assert_includes generator.received[:system_prompt], "first 15 seconds"
    assert_includes generator.received[:system_prompt], "Plain narration text only"
    assert_includes generator.received[:user_prompt], "The hidden engineering of suspension bridges"
    assert_includes generator.received[:user_prompt], "Tone: dramatic"
    assert_includes generator.received[:user_prompt], "4 minutes (about 600 words)"
  end

  test "a rewrite saves a new version and keeps the previous one" do
    @project.scripts.create!(body: "Original draft", version: 1)
    @project.update!(status: :script_ready)

    perform_with(FakeGenerator.new(generation_result(text: "Rewritten draft")))

    assert_equal [ "Original draft", "Rewritten draft" ], @project.reload.scripts.map(&:body)
    assert_equal [ 1, 2 ], @project.scripts.map(&:version)
  end

  test "clears the generating flag and keeps the project unchanged when the provider fails" do
    perform_with(FakeGenerator.new(nil, Ai::TextGenerator::Error.new("timeout")))

    @project.reload
    assert_not @project.script_generating?
    assert_nil @project.latest_script
    assert @project.draft?
    assert_equal 0, @project.api_usages.count
  end

  test "clears the generating flag even when an unexpected error escapes" do
    assert_raises(ActiveRecord::RecordInvalid) do
      perform_with(FakeGenerator.new(generation_result(text: "")))
    end

    assert_not @project.reload.script_generating?
  end
end
