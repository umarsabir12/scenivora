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

    def initialize(error: nil, plans: nil, queries: nil)
      @error = error
      @plans = plans
      @queries = queries
      @calls = 0
    end

    def call(topic:, scenes:)
      @calls += 1
      raise @error if @error

      plans = @plans || scenes.to_h do |scene|
        [ scene.position, Ai::ScenePlanner::Plan.new(position: scene.position, visual_intent: "Scene #{scene.position}",
          subject_type: "generic_scene", search_queries: @queries || [ "Tesla #{scene.position}" ], ai_fallback_allowed: true) ]
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

  # Returns the given videos for every query (none by default), and can be told to fail.
  class FakeVideoSearch
    attr_reader :queries

    def initialize(videos: [], error: nil)
      @videos = videos
      @error = error
      @queries = []
    end

    def search(query, limit: 2)
      @queries << query
      raise @error if @error

      @videos.first(limit)
    end
  end

  # Stands in for the relevance check: keeps every candidate in order unless told otherwise.
  class FakeRanker
    attr_reader :calls

    def initialize(keep: nil, error: nil)
      @keep = keep
      @error = error
      @calls = 0
    end

    def call(topic:, scenes:)
      @calls += 1
      raise @error if @error

      kept = scenes.to_h { |scene| [ scene.position, @keep ? @keep.call(scene) : scene.images.map(&:id) ] }
      Ai::CandidateRanker::Result.new(kept: kept, total_tokens: 500, cost_usd: BigDecimal("0.0001"))
    end
  end

  # Stands in for the picture check: approves the first candidate unless told otherwise.
  class FakeVerifier
    attr_reader :calls

    def initialize(choose: ->(candidates) { candidates.first&.id }, error: nil)
      @choose = choose
      @error = error
      @calls = 0
    end

    def call(scene:, candidates:)
      @calls += 1
      raise @error if @error

      Ai::ImageVerifier::Result.new(choice_id: @choose.call(candidates), reason: "Shows the scene.", total_tokens: 900,
                                    cost_usd: BigDecimal("0.0002"))
    end
  end

  # Stands in for the second-chance query writer: no new queries unless given some.
  class FakeRewriter
    attr_reader :calls

    def initialize(queries: [])
      @queries = queries
      @calls = 0
    end

    def call(topic:, scenes:)
      @calls += 1
      Ai::QueryRewriter::Result.new(queries: scenes.to_h { |scene| [ scene.position, @queries ] }, total_tokens: 300,
                                    cost_usd: BigDecimal("0.0001"))
    end
  end

  def run_job(commons: FakeSearch.new, pixabay: nil, planner: FakePlanner.new, videos: FakeVideoSearch.new, ranker: FakeRanker.new,
              verifier: FakeVerifier.new, rewriter: FakeRewriter.new)
    with_stubbed_new(Media::CommonsSearch, commons) do
      with_stubbed_new(Media::CommonsVideoSearch, videos) do
        with_stubbed_new(Media::PixabaySearch, pixabay || FakeSearch.new(provider: "pixabay")) do
          with_stubbed_new(Ai::ScenePlanner, planner) do
            with_stubbed_new(Ai::CandidateRanker, ranker) do
              with_stubbed_new(Ai::ImageVerifier, verifier) do
                with_stubbed_new(Ai::QueryRewriter, rewriter) do
                  FindSceneImagesJob.perform_now(@project)
                end
              end
            end
          end
        end
      end
    end
  end

  # Titled so it matches the fake planner's queries ("Tesla 1", "Partition 4").
  def video(name, duration_ms: 60_000, title: "Tesla and Partition footage #{name}")
    Media::VideoResult.new(provider: "wikimedia_commons", title: title, video_url: "https://upload.wikimedia.org/#{name}.webm",
                           poster_url: "https://upload.wikimedia.org/#{name}.jpg", page_url: "https://commons.example/#{name}",
                           credit: "Archive", license: "Public domain", duration_ms: duration_ms)
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

  # Finds results only for the queries it is given, and records every search.
  class PickySearch
    attr_reader :queries

    def initialize(found:, failing: [])
      @found = found
      @failing = failing
      @queries = []
    end

    def search(query, limit: 3)
      @queries << query
      raise Media::Error, "api.wikimedia.org responded with 500" if @failing.include?(query)
      return [] unless @found.include?(query)

      Array.new(limit) do |i|
        Media::ImageResult.new(provider: "wikimedia_commons", image_url: "https://img.example/#{query.parameterize}-#{i}.jpg",
                               page_url: "https://src.example", credit: "Jane", license: "CC0")
      end
    end
  end

  def single_plan(queries)
    FakePlanner.new(queries: queries)
  end

  test "falls back to broader queries when the planner's queries find nothing" do
    search = PickySearch.new(found: [ "Karachi" ])

    run_job(commons: search, planner: single_plan([ "Karachi 1876", "historical Karachi harbour" ]))

    scene = @project.reload.scenes.first
    assert_equal FindSceneImagesJob::POOL_SIZE / 2, scene.images.count
    assert_includes search.queries, "Karachi"
    assert_equal "Karachi 1876", search.queries.first
    assert_nil scene.search_error
  end

  test "a failed search moves on to the next query instead of failing the scene" do
    search = PickySearch.new(found: [ "Karachi" ], failing: [ "Karachi 1876" ])

    run_job(commons: search, planner: single_plan([ "Karachi 1876", "Karachi" ]))

    scene = @project.reload.scenes.first
    assert_equal FindSceneImagesJob::POOL_SIZE / 2, scene.images.count
    assert_nil scene.search_error
  end

  test "stops after the per-scene search limit" do
    search = PickySearch.new(found: [])

    run_job(commons: search, planner: single_plan([ "one two three four five six seven" ]))

    scenes = @project.reload.scenes.size
    assert_equal FindSceneImagesJob::MAX_SEARCHES_PER_SCENE * scenes, search.queries.size
  end

  test "the hook scenes look for video first and select it" do
    videos = FakeVideoSearch.new(videos: [ video("refugees"), video("train") ])

    run_job(videos: videos)

    first = @project.reload.scenes.find_by(position: 1)
    selected = first.selected_image
    assert selected.video?
    assert_equal "https://upload.wikimedia.org/refugees.webm", selected.image_url
    assert_equal "https://upload.wikimedia.org/refugees.jpg", selected.poster_url
    assert_equal 15_000, selected.clip_start_ms, "a quarter of the way into a 60 s video"
    assert first.images.reject(&:video?).any?, "images are kept as alternatives"
  end

  test "later scenes stay on images unless the planner prefers video" do
    videos = FakeVideoSearch.new(videos: [ video("refugees") ])

    run_job(videos: videos)

    later = @project.reload.scenes.find_by(position: 3)
    assert_not later.selected_image.video?
    assert later.images.none?(&:video?)
  end

  test "a scene the planner marks for video gets video even when it isn't a hook scene" do
    planner = FakePlanner.new(plans: nil)
    planner.define_singleton_method(:call) do |topic:, scenes:|
      plans = scenes.to_h do |scene|
        [ scene.position, Ai::ScenePlanner::Plan.new(position: scene.position, visual_intent: "x", subject_type: "historical_event",
            search_queries: [ "Partition #{scene.position}" ], ai_fallback_allowed: true, prefer: "video") ]
      end
      Ai::ScenePlanner::Result.new(plans: plans, total_tokens: 700, cost_usd: BigDecimal("0.0001"))
    end

    run_job(planner: planner, videos: FakeVideoSearch.new(videos: [ video("refugees") ]))

    assert @project.reload.scenes.find_by(position: 4).selected_image.video?
  end

  test "a failed video search leaves the scene with images" do
    run_job(videos: FakeVideoSearch.new(error: Media::Error.new("api.wikimedia.org responded with 500")))

    first = @project.reload.scenes.find_by(position: 1)
    assert_nil first.search_error
    assert first.selected_image.present?
    assert_not first.selected_image.video?
  end

  test "a short video starts at the beginning so the scene fits" do
    run_job(videos: FakeVideoSearch.new(videos: [ video("short", duration_ms: 8_000) ]))

    assert_equal 0, @project.reload.scenes.find_by(position: 1).selected_image.clip_start_ms
  end

  test "a video whose title shares no word with the query is not used" do
    off_topic = video("wall", title: "Tear down this wall")

    run_job(videos: FakeVideoSearch.new(videos: [ off_topic ]))

    assert @project.reload.scenes.find_by(position: 1).images.none?(&:video?)
  end

  test "videos use only the planner's own queries, not broadened ones" do
    videos = FakeVideoSearch.new(videos: [])

    run_job(planner: single_plan([ "Karachi 1876 harbour" ]), videos: videos)

    assert_equal [ "Karachi 1876 harbour" ], videos.queries.uniq
  end

  test "the relevance check removes rejected candidates and selects its first choice" do
    search = PickySearch.new(found: [ "Karachi" ])
    ranker = FakeRanker.new(keep: ->(scene) { scene.images.map(&:id).reverse.first(2) })

    run_job(commons: search, planner: single_plan([ "Karachi" ]), ranker: ranker)

    scene = @project.reload.scenes.first
    assert_equal 2, scene.images.count
    assert scene.images.max_by(&:id).selected?, "the ranker's first choice is selected"
    assert_equal 500, @project.api_usages.find_by(operation: "candidate_rank").units
  end

  test "a scene whose candidates are all rejected asks the user to step in" do
    run_job(ranker: FakeRanker.new(keep: ->(_scene) { [] }))

    scene = @project.reload.scenes.first
    assert scene.images.none?
    assert_equal FindSceneImagesJob::NO_MATCH, scene.search_error
  end

  test "a failed relevance check keeps the candidates as they were" do
    run_job(ranker: FakeRanker.new(error: Ai::Error.new("Text generation failed: quota")))

    scene = @project.reload.scenes.first
    assert scene.selected_image.present?
    assert_nil @project.api_usages.find_by(operation: "candidate_rank")
  end

  test "a picture that passes the check is selected and marked checked" do
    run_job

    scene = @project.reload.scenes.first
    assert_equal "verified", scene.media_check
    assert_equal "Shows the scene.", scene.media_note
    assert scene.selected_image.present?
    assert @project.api_usages.where(operation: "image_check").exists?
  end

  test "when no picture passes, the scene's picture is deselected and an AI image is suggested" do
    run_job(verifier: FakeVerifier.new(choose: ->(_candidates) { nil }))

    scene = @project.reload.scenes.first
    assert scene.ai_suggested?
    assert_nil scene.selected_image
    assert_match "No real picture fits", scene.media_note
    assert scene.images.any?, "candidates stay available for a manual pick"
  end

  test "a failed picture check flags the scene for review and keeps its picture" do
    run_job(verifier: FakeVerifier.new(error: Ai::Error.new("Text generation failed: quota")))

    scene = @project.reload.scenes.first
    assert_nil scene.media_check
    assert_match "Review this scene yourself", scene.media_note
    assert scene.selected_image.present?
  end

  test "AI-for-every-scene mode skips searching and suggests AI everywhere" do
    @project.update!(settings: { "image_mode" => "ai_all" })
    search = PickySearch.new(found: [ "Karachi" ])
    verifier = FakeVerifier.new

    run_job(commons: search, verifier: verifier)

    assert_empty search.queries
    assert_equal 0, verifier.calls
    assert @project.reload.scenes.all?(&:ai_suggested?)
  end

  test "the pool gathers candidates from all of the planner's queries, not just the first that answers" do
    search = PickySearch.new(found: [ "Culebra Cut steam shovel", "Gatun Locks construction" ])

    run_job(commons: search, planner: single_plan([ "Culebra Cut steam shovel", "Gatun Locks construction", "Panama Canal" ]))

    scene = @project.reload.scenes.first
    titles = scene.images.map(&:image_url)
    assert titles.any? { |url| url.include?("culebra-cut") }
    assert titles.any? { |url| url.include?("gatun-locks") }
    assert_equal FindSceneImagesJob::POOL_SIZE, scene.images.count
  end

  test "scenes left without a picture get new queries and are searched and checked once more" do
    search = PickySearch.new(found: [ "Culebra Cut steam shovel" ])
    rewriter = FakeRewriter.new(queries: [ "Culebra Cut steam shovel" ])

    run_job(commons: search, planner: single_plan([ "Panama Canal workers digging" ]), rewriter: rewriter)

    scene = @project.reload.scenes.first
    assert_equal 1, rewriter.calls
    assert_equal "verified", scene.media_check
    assert_equal "Culebra Cut steam shovel", scene.search_query
    assert scene.selected_image.image_url.include?("culebra-cut")
    assert @project.api_usages.where(operation: "query_rewrite").exists?
  end

  test "the second chance isn't used when every scene already has a picture" do
    rewriter = FakeRewriter.new(queries: [ "anything" ])

    run_job(rewriter: rewriter)

    assert_equal 0, rewriter.calls
  end
end
