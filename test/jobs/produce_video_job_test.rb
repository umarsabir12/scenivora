require "test_helper"

class ProduceVideoJobTest < ActiveJob::TestCase
  SCRIPT = "In December 1922 HMS Calypso reached Corfu.\n\nA baby prince was carried aboard in a fruit box.\n\n" \
           "The family sailed for Brindisi.\n\nThey settled at Saint-Cloud near Paris.".freeze

  # Stands in for ScriptWriter: saves a fixed script, or fails.
  class FakeWriter
    def initialize(error: nil)
      @error = error
    end

    def write(project)
      raise @error if @error

      project.scripts.create!(body: SCRIPT, version: project.next_script_version)
    end
  end

  setup do
    @user = users(:one)
    @user.update!(credits_balance: 100)
    @project = @user.projects.create!(prompt: "Prince Philip's escape", tone: "dramatic", target_length_minutes: 3,
                                      settings: { "production" => { "step" => "writing" } })
    @searches = 0
  end

  # The picture search marks the scenes given as needing an AI image and the rest as checked.
  def produce(writer: FakeWriter.new, needs_ai: [ 2, 4 ])
    searches = 0
    find = lambda do |project|
      searches += 1
      project.scenes.each do |scene|
        scene.update!(media_check: needs_ai.include?(scene.position) ? "ai_suggested" : "verified",
                      plan: { "visual_intent" => "Shot #{scene.position}" })
      end
    end
    with_stubbed_new(ScriptWriter, writer) do
      with_stubbed_method(FindSceneImagesJob, :perform_now, find) do
        ProduceVideoJob.perform_now(@project)
      end
    end
    @searches = searches
  end

  test "writes the script, lays it out as scenes, finds pictures and starts AI images where needed" do
    produce

    @project.reload
    assert @project.script_ready?
    assert @project.storyboard?
    assert_equal "done", @project.production_step
    assert_equal 1, @searches
    scenes = @project.scenes.to_a
    assert_equal 4, scenes.size
    assert_equal "In December 1922 HMS Calypso reached Corfu.", scenes.first.text
    assert_equal [ 0, 2_800 ], scenes.first(2).map(&:start_ms)
    assert_equal [ 2, 4 ], scenes.select(&:ai_generating?).map(&:position)
    assert_equal 100 - 2 * CreditPricing.ai_image, @user.reload.credits_balance
    assert_enqueued_jobs 2, only: GenerateSceneImageJob
  end

  test "a new storyboard needs a new voice" do
    track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, confirmed_at: Time.current)

    produce

    assert_nil track.reload.confirmed_at
  end

  test "AI images are capped, and stop when the credits run out, with a note" do
    @user.update!(credits_balance: CreditPricing.ai_image)

    produce

    @project.reload
    assert_equal [ 2 ], @project.scenes.select(&:ai_generating?).map(&:position)
    assert_equal "1 scene still needs an AI image (not enough credits).", @project.settings.dig("production", "note")
    assert_equal 0, @user.reload.credits_balance
  end

  test "no more than MAX_AI_IMAGES are started at once, hook scenes first" do
    long_script = (1..10).map { |n| "Shot #{n} shows HMS Calypso at sea." }.join("\n\n")
    writer = FakeWriter.new
    writer.define_singleton_method(:write) { |project| project.scripts.create!(body: long_script, version: 1) }

    produce(writer: writer, needs_ai: (1..10).to_a)

    generating = @project.reload.scenes.select(&:ai_generating?).map(&:position)
    assert_equal (1..ProduceVideoJob::MAX_AI_IMAGES).to_a, generating
    assert_equal "2 scenes still need an AI image.", @project.settings.dig("production", "note")
  end

  test "tells the user when the brief's story couldn't be verified" do
    @project.update!(settings: @project.settings.merge("research" => { "story_check" => { "status" => "unverified", "note" => "No source names the women." } }))

    produce(needs_ai: [])

    assert_equal "The story in your brief couldn't be verified, so the script tells it as a story, not as fact. No source names the women.",
                 @project.reload.settings.dig("production", "note")
  end

  test "when writing fails, the run is marked failed and the project stays a draft" do
    produce(writer: FakeWriter.new(error: Ai::Error.new("Text generation failed: quota")))

    @project.reload
    assert_equal "failed", @project.production_step
    assert_equal ProduceVideoJob::FAILED, @project.settings.dig("production", "error")
    assert @project.draft?
    assert_equal 0, @searches
  end

  test "start_production! starts one run at a time" do
    @project.update!(status: :script_ready, settings: {})

    assert_enqueued_jobs 1, only: ProduceVideoJob do
      @project.start_production!
      @project.start_production!
    end
    assert @project.draft?
    assert @project.producing?
  end
end
