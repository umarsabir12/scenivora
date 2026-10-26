require "test_helper"

class FindSceneImagesJobTest < ActiveJob::TestCase
  # Returns one fixed candidate per query, and can be told to fail.
  class FakeSearch
    def initialize(error: nil, provider: "wikimedia_commons")
      @error = error
      @provider = provider
    end

    def search(query, limit: 3)
      raise @error if @error

      [ Media::ImageResult.new(provider: @provider, image_url: "https://img.example/#{query.parameterize}.jpg",
                               page_url: "https://src.example/#{query.parameterize}", credit: "Jane",
                               license: "CC BY 4.0") ]
    end
  end

  # Stands in for the scene planner, so no test makes a paid call. Counts how often it is called.
  class FakePlanner
    attr_reader :calls

    def initialize(error: nil, plans: nil)
      @error = error
      @plans = plans
      @calls = 0
    end

    def call(topic:, scenes:)
      @calls += 1
      raise @error if @error

      plans = @plans || scenes.to_h do |scene|
        [ scene.position, Ai::ScenePlanner::Plan.new(position: scene.position, visual_intent: "Scene #{scene.position}",
          subject_type: "generic_scene", search_queries: [ "Tesla #{scene.position}" ], ai_fallback_allowed: true) ]
      end
      Ai::ScenePlanner::Result.new(plans: plans, total_tokens: 700, cost_usd: BigDecimal("0.0001"))
    end
  end

  setup do
    @project = users(:one).projects.create!(prompt: "Nikola Tesla", tone: "documentary", target_length_minutes: 3)
    @project.scripts.create!(body: "Nikola Tesla was born in Croatia. " * 20, version: 1)
    @project.script_ready!
    @track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 60_000,
      script_digest: @project.latest_script.digest, confirmed_at: Time.current)
    @track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
    @track.update!(status: "ready")
  end

  def run_job(commons: FakeSearch.new, pixabay: nil, planner: FakePlanner.new)
    with_stubbed_new(Media::CommonsSearch, commons) do
      with_stubbed_new(Media::PixabaySearch, pixabay || FakeSearch.new(provider: "pixabay")) do
        with_stubbed_new(Ai::ScenePlanner, planner) do
          FindSceneImagesJob.perform_now(@project)
        end
      end
    end
  end

  test "creates timed scenes and stores the first candidate as selected" do
    run_job

    scenes = @project.reload.scenes
    assert scenes.size >= 5
    assert_equal 60_000, scenes.last.end_ms
    scenes.each do |scene|
      assert scene.selected_image.present?
      assert_equal "Jane", scene.selected_image.credit
      assert_equal "CC BY 4.0", scene.selected_image.license
    end
  end

  test "uses the planner's first query for each scene and records its cost" do
    plan = Ai::ScenePlanner::Plan.new(position: 1, visual_intent: "Portrait", subject_type: "real_person",
                                      search_queries: [ "Nikola Tesla 1890" ], ai_fallback_allowed: false)

    run_job(planner: FakePlanner.new(plans: { 1 => plan }.merge((2..6).to_h { |n| [ n, plan.with(position: n) ] })))

    first = @project.scenes.find_by(position: 1)
    assert_equal "Nikola Tesla 1890", first.search_query
    assert_equal "real_person", first.plan["subject_type"]
    assert_equal 700, @project.api_usages.find_by(operation: "scene_plan").units
  end

  test "an unchanged script reuses the existing plan instead of calling the planner again" do
    planner = FakePlanner.new
    run_job(planner: planner)
    scene_ids = @project.reload.scenes.pluck(:id)

    run_job(planner: planner)

    assert_equal 1, planner.calls
    assert_equal scene_ids, @project.reload.scenes.pluck(:id)
    assert_equal 1, @project.api_usages.where(operation: "scene_plan").count
  end

  test "an edited script plans again" do
    planner = FakePlanner.new
    run_job(planner: planner)
    @project.latest_script.update!(body: "A completely new narration about Tesla's later years. " * 20)

    run_job(planner: planner)

    assert_equal 2, planner.calls
  end

  test "when planning fails, scenes get a retry message, no images are searched, and no plan is kept" do
    run_job(planner: FakePlanner.new(error: Ai::Error.new("Text generation failed: quota")))

    scenes = @project.reload.scenes
    assert scenes.any?
    assert scenes.all? { |scene| scene.search_error == FindSceneImagesJob::PLANNING_FAILED }
    assert scenes.all? { |scene| scene.images.empty? }
    assert_nil @project.api_usages.find_by(operation: "scene_plan")
    assert_nil @project.settings["scene_key"]
  end

  test "a failed search leaves that scene with a message and the others still work" do
    run_job(commons: FakeSearch.new(error: Media::Error.new("upload.wikimedia.org could not be used")))

    scenes = @project.reload.scenes
    assert scenes.all? { |scene| scene.search_error.present? }
    assert scenes.all? { |scene| scene.images.empty? }
  end

  test "Pixabay is added only when there are fewer Commons results than the limit" do
    run_job(commons: FakeSearch.new, pixabay: FakeSearch.new(provider: "pixabay"))

    assert @project.reload.scenes.first.images.map(&:provider).include?("wikimedia_commons")
  end

  test "clears the searching flag when finished" do
    @project.update!(settings: { "scenes_searching" => true })

    run_job

    assert_nil @project.reload.settings["scenes_searching"]
  end

  test "refuses to run before the voice is confirmed" do
    @track.update!(confirmed_at: nil)

    assert_raises(Ai::Error) { run_job }
  end
end
