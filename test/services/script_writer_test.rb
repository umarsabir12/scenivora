require "test_helper"

class ScriptWriterTest < ActiveSupport::TestCase
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
  end

  def generation_result(text: "A gripping hook.\n\nThe turning point.", total_tokens: 1_200, cost_usd: BigDecimal("0.00032"))
    Ai::TextGenerator::Result.new(
      text: text, provider: "openai", model: "gpt-4o-mini", total_tokens: total_tokens, cost_usd: cost_usd
    )
  end

  # Without a researcher the Director is off, so the script is written from the brief alone.
  def perform_with(generator, researcher: nil, writer: nil)
    with_stubbed_method(Ai::Director, :enabled?, -> { !researcher.nil? }) do
      with_stubbed_new(Ai::Researcher, researcher) do
        with_stubbed_new(Ai::ResearchGenerator, writer) do
          with_stubbed_new(Ai::TextGenerator, generator) do
            ScriptWriter.new.write(@project)
          end
        end
      end
    end
  end

  # Stands in for the research step: canned research, or an error. Counts its calls.
  class FakeResearcher
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = 0
    end

    def call(_project)
      @calls += 1
      raise @error if @error

      Ai::Researcher::Research.new(
        facts: [ "Suspension cables are spun from thousands of steel wires." ], articles: [ "Suspension bridge" ],
        visual_subjects: [ { "name" => "Golden Gate Bridge", "kind" => "building", "article" => "Golden Gate Bridge", "year" => "1937" } ],
        uncertain: [ "Legend says a worker is sealed in a tower." ], total_tokens: 20_000, cost_usd: BigDecimal("0.2"),
        searches: 4, dropped_articles: [])
    end
  end

  # Stands in for the strong model that writes the script from the research.
  # texts: what each call returns, in order (the last one repeats).
  class FakeWriter
    attr_reader :args, :calls

    def initialize(text: "The Golden Gate Bridge opened in 1937.", texts: nil, error: nil)
      @texts = texts || [ text ]
      @error = error
      @calls = []
    end

    def call(**args)
      @args = args
      @calls << args
      raise @error if @error

      Ai::ResearchGenerator::Result.new(text: @texts[[ @calls.size - 1, @texts.size - 1 ].min], provider: "openai",
                                        model: "gpt-5.5", total_tokens: 3_000, cost_usd: BigDecimal("0.05"), searches: 0)
    end
  end

  test "saves the script as version 1" do
    perform_with(FakeGenerator.new(generation_result))

    script = @project.reload.latest_script
    assert_equal 1, script.version
    assert_equal "A gripping hook.\n\nThe turning point.", script.body
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
    assert_includes generator.received[:system_prompt].squish, "Each paragraph is one shot of the video"
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

  test "when the provider fails, nothing is saved and the error is raised" do
    assert_raises(Ai::Error) { perform_with(FakeGenerator.new(nil, Ai::TextGenerator::Error.new("timeout"))) }

    assert_nil @project.reload.latest_script
    assert_equal 0, @project.api_usages.count
  end

  test "researches first, then writes the script from the facts with the strong model" do
    @project.update!(category: "science", instructions: "Focus on the cables.")
    writer = FakeWriter.new
    fallback = FakeGenerator.new(generation_result)

    perform_with(fallback, researcher: FakeResearcher.new, writer: writer)

    @project.reload
    assert_equal "The Golden Gate Bridge opened in 1937.", @project.latest_script.body
    assert_nil fallback.received
    prompt = writer.args[:input]
    assert_includes prompt, "- Suspension cables are spun from thousands of steel wires."
    assert_includes prompt, "- Golden Gate Bridge (building, 1937)"
    assert_includes prompt, "- Legend says a worker is sealed in a tower."
    assert_includes prompt, "The creator's instructions: Focus on the cables."
    assert_includes prompt, "Category: science."
    assert_includes writer.args[:instructions], "Every paragraph names at least one concrete visual subject"
    assert_nil writer.args[:domains]
    assert_equal [ "Suspension cables are spun from thousands of steel wires." ], @project.settings["research"]["facts"]
    assert_equal({ "research" => BigDecimal("0.2"), "script" => BigDecimal("0.05") },
                 @project.api_usages.pluck(:operation, :cost_usd).to_h)
  end

  test "asks for the target length, and shortens a script that is much too long once" do
    long = "word " * 700
    writer = FakeWriter.new(texts: [ long, "A tight script." ])

    perform_with(FakeGenerator.new(generation_result), researcher: FakeResearcher.new, writer: writer)

    assert_includes writer.calls.first[:input], "Word count: between 540 and 660 words."
    assert_equal 2, writer.calls.size
    assert_includes writer.calls.second[:instructions], "Shorten this narration script"
    assert_includes writer.calls.second[:input], "Word count: about 600"
    assert_equal "A tight script.", @project.reload.latest_script.body
    assert_equal BigDecimal("0.1"), @project.api_usages.find_by(operation: "script").cost_usd
  end

  test "a script within the length is not shortened" do
    writer = FakeWriter.new(text: "word " * 655)

    perform_with(FakeGenerator.new(generation_result), researcher: FakeResearcher.new, writer: writer)

    assert_equal 1, writer.calls.size
  end

  test "a rewrite with the same brief reuses the stored research" do
    researcher = FakeResearcher.new
    perform_with(FakeGenerator.new(generation_result), researcher: researcher, writer: FakeWriter.new)

    perform_with(FakeGenerator.new(generation_result), researcher: researcher, writer: FakeWriter.new(text: "Second draft."))

    assert_equal 1, researcher.calls
    assert_equal "Second draft.", @project.reload.latest_script.body
    assert_equal 1, @project.api_usages.where(operation: "research").count
  end

  test "a changed brief researches again" do
    researcher = FakeResearcher.new
    perform_with(FakeGenerator.new(generation_result), researcher: researcher, writer: FakeWriter.new)
    @project.reload.update!(instructions: "Focus on the towers instead.")

    perform_with(FakeGenerator.new(generation_result), researcher: researcher, writer: FakeWriter.new)

    assert_equal 2, researcher.calls
  end

  test "when research fails, the script is written from the brief as before" do
    fallback = FakeGenerator.new(generation_result(text: "From the brief."))

    perform_with(fallback, researcher: FakeResearcher.new(error: Ai::Error.new("Research call failed: timeout")), writer: FakeWriter.new)

    @project.reload
    assert_equal "From the brief.", @project.latest_script.body
    assert_includes fallback.received[:user_prompt], "The hidden engineering of suspension bridges"
    assert_nil @project.settings["research"]
    assert_equal [ "script" ], @project.api_usages.pluck(:operation)
  end

  test "when the strong model fails, the cheap model writes from the brief and the research is kept" do
    fallback = FakeGenerator.new(generation_result(text: "From the brief."))

    perform_with(fallback, researcher: FakeResearcher.new, writer: FakeWriter.new(error: Ai::Error.new("Research call failed: 500")))

    @project.reload
    assert_equal "From the brief.", @project.latest_script.body
    assert @project.settings["research"].present?
  end

  test "an empty script is not saved" do
    assert_raises(ActiveRecord::RecordInvalid) { perform_with(FakeGenerator.new(generation_result(text: ""))) }

    assert_equal 0, @project.reload.api_usages.count
  end
end
