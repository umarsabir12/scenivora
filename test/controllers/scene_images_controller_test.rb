require "test_helper"

class SceneImagesControllerTest < ActionDispatch::IntegrationTest
  class FakeSearch
    def initialize(results: [], error: nil)
      @results = results
      @error = error
    end

    def search(query, limit: 6)
      raise @error if @error

      @results
    end
  end

  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How tides work", tone: "documentary", target_length_minutes: 3)
    @scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)
    @picked = @scene.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/a.jpg",
      credit: "Jane", license: "CC0", selected: true)
    @other = @scene.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/b.jpg",
      credit: "Bo", license: "CC BY 4.0")
    sign_in @user
  end

  def result(url)
    Media::ImageResult.new(provider: "wikimedia_commons", image_url: url, page_url: "https://src.example",
                           credit: "Kim", license: "Public domain")
  end

  test "selecting a candidate makes it the only selected image" do
    post select_scene_image_url(@scene, @other)

    assert_redirected_to project_scenes_url(@project, scene: @scene.id, anchor: "swap")
    assert @other.reload.selected?
    assert_not @picked.reload.selected?
  end

  test "remove leaves the scene without a selected image but keeps its candidates" do
    delete scene_clear_image_url(@scene)

    assert_nil @scene.reload.selected_image
    assert_equal 2, @scene.images.count
  end

  test "uploading an image stores it and selects it" do
    post scene_images_url(@scene), params: { file: fixture_file_upload("scene.png", "image/png") }

    upload = @scene.images.find_by(provider: "upload")
    assert upload.file.attached?
    assert upload.selected?
    assert_not @picked.reload.selected?
  end

  test "uploading a file that is not an image is refused" do
    assert_no_difference -> { @scene.images.count } do
      post scene_images_url(@scene), params: { file: fixture_file_upload("notes.txt", "text/plain") }
    end

    assert_match "must be a JPEG, PNG or WebP image", flash[:alert]
  end

  test "search replaces the unpicked candidates and keeps the selected image" do
    search = FakeSearch.new(results: [ result("https://img.example/new1.jpg"), result("https://img.example/a.jpg") ])

    with_stubbed_new(Media::CommonsSearch, search) do
      post scene_search_url(@scene), params: { query: "moon over the sea" }
    end

    urls = @scene.images.reload.map(&:image_url)
    assert_equal [ "https://img.example/a.jpg", "https://img.example/new1.jpg" ], urls
    assert @picked.reload.selected?
    assert_equal "moon over the sea", @scene.reload.search_query
  end

  test "a failed search keeps the existing candidates and shows a message" do
    with_stubbed_new(Media::CommonsSearch, FakeSearch.new(error: Media::Error.new("offline"))) do
      post scene_search_url(@scene), params: { query: "moon" }
    end

    assert_equal "Image search failed. Try again later.", flash[:alert]
    assert_equal 2, @scene.images.count
  end

  test "an empty search is refused without calling Commons" do
    post scene_search_url(@scene), params: { query: "  " }

    assert_equal "Enter something to search for.", flash[:alert]
  end

  test "another user's scene cannot be changed" do
    other_project = users(:two).projects.create!(prompt: "Someone else's video", tone: "casual", target_length_minutes: 3)
    other_scene = other_project.scenes.create!(position: 1, text: "Private.", start_ms: 0, duration_ms: 10_000)

    delete scene_clear_image_url(other_scene)

    assert_response :not_found
  end

  test "generating charges credits, marks the scene, and queues the job" do
    @user.grant_credits!(10, reason: "manual_grant")

    assert_enqueued_with(job: GenerateSceneImageJob) do
      post scene_ai_image_url(@scene), params: { prompt: "Moon over a calm sea" }
    end

    assert_equal 10 - CreditPricing.ai_image, @user.reload.credits_balance
    assert @scene.reload.ai_generating?
    assert_redirected_to project_scenes_url(@project, scene: @scene.id, source: "ai", anchor: "swap")
  end

  test "generating without enough credits is refused and charges nothing" do
    assert_no_enqueued_jobs do
      post scene_ai_image_url(@scene), params: { prompt: "Moon over a calm sea" }
    end

    assert_match "You need #{CreditPricing.ai_image} credits", flash[:alert]
    assert_equal 0, @user.reload.credits_balance
    assert_not @scene.reload.ai_generating?
  end

  test "a scene the planner marked as a real person cannot use AI images" do
    @user.grant_credits!(10, reason: "manual_grant")
    @scene.update!(plan: { "ai_fallback_allowed" => false })

    assert_no_enqueued_jobs do
      post scene_ai_image_url(@scene), params: { prompt: "A portrait" }
    end

    assert_equal 10, @user.reload.credits_balance
  end

  test "a second request while one is generating does not charge again" do
    @user.grant_credits!(10, reason: "manual_grant")
    @scene.update!(ai_status: "generating")

    assert_no_enqueued_jobs do
      post scene_ai_image_url(@scene), params: { prompt: "Moon over a calm sea" }
    end

    assert_equal 10, @user.reload.credits_balance
  end

  test "an empty description is refused" do
    @user.grant_credits!(10, reason: "manual_grant")

    post scene_ai_image_url(@scene), params: { prompt: " " }

    assert_equal "Describe the image you want.", flash[:alert]
    assert_equal 10, @user.reload.credits_balance
  end
end
