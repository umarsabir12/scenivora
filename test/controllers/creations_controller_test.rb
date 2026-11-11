require "test_helper"

class CreationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(credits_balance: 10)
    sign_in @user
  end

  def speech_params(prompt: "Hello there.", voice: "onyx", speed: "1.0")
    { creation: { model_key: "openai-tts-1", prompt: prompt, options: { voice: voice, speed: speed } } }
  end

  test "text to speech shows the model picker, voices and the user's past results" do
    @user.creations.create!(kind: "speech", model_key: "openai-tts-1", prompt: "An older one", status: "failed",
                            error: "Boom", options: { "voice" => "alloy", "speed" => 1.0 })

    get creations_url("speech")

    assert_response :success
    assert_select "h1", "Text to speech"
    assert_select "select[name=?] option", "creation[model_key]", text: /OpenAI tts-1 · 1 credit per 1,000 characters/
    assert_select "input[type=radio][name=?]", "creation[options][voice]", count: Ai::SpeechGenerator::VOICES.size
    assert_select "li", text: /An older one/
  end

  test "a tool without models says so and has no form" do
    get creations_url("video")

    assert_response :success
    assert_select "h1", "Create video"
    assert_match "Models coming soon", response.body
    assert_select "form[action=?]", creations_path("video"), count: 0
  end

  test "an unknown tool is not found" do
    get "/create/podcast"

    assert_response :not_found
  end

  test "generating charges credits per started 1,000 characters and queues the job" do
    assert_enqueued_with(job: GenerateCreationJob) do
      post creations_url("speech"), params: speech_params(prompt: "a" * 1_500)
    end

    creation = @user.creations.last
    assert_redirected_to creations_url("speech")
    assert_equal 2, creation.credits_charged
    assert_equal 8, @user.reload.credits_balance
    assert_equal({ "voice" => "onyx", "speed" => "1.0" }, creation.options)
    assert_equal "create_speech", @user.credit_transactions.last.reason
  end

  test "not enough credits charges nothing and says so" do
    @user.update!(credits_balance: 1)

    assert_no_enqueued_jobs do
      post creations_url("speech"), params: speech_params(prompt: "a" * 2_500)
    end

    assert_equal "You don't have enough credits for this. You have 1.", flash[:alert]
    assert_equal 1, @user.reload.credits_balance
    assert_equal 0, @user.creations.count
  end

  test "an unknown voice or model is refused before charging" do
    post creations_url("speech"), params: speech_params(voice: "darth")
    assert_equal "Choose a voice", flash[:alert]

    post creations_url("speech"), params: speech_params.deep_merge(creation: { model_key: "nope" })
    assert_match "isn't offered", flash[:alert]

    assert_equal 10, @user.reload.credits_balance
    assert_equal 0, @user.creations.count
  end

  test "the sidebar links each tool and marks the ones without models" do
    get creations_url("speech")

    assert_select "a[href=?][aria-current=page]", creations_path("speech"), text: /Text to speech/
    assert_select "a[href=?]", creations_path("video"), text: /Soon/
  end

  def image_params(style: "photo", size: "1024x1024")
    { creation: { model_key: "openai-gpt-image-1-mini", prompt: "A lighthouse at dawn", options: { style: style, size: size } } }
  end

  test "create image shows the model with its price, styles and sizes" do
    get creations_url("image")

    assert_select "h1", "Create image"
    assert_select "select[name=?] option", "creation[model_key]", text: /gpt-image-1-mini · 5 credits per image/
    assert_select "input[type=radio][name=?]", "creation[options][style]", count: Creation::IMAGE_STYLES.size
    assert_select "input[type=radio][name=?]", "creation[options][size]", count: Creation::IMAGE_SIZES.size
  end

  test "an image costs its flat credit price" do
    assert_enqueued_with(job: GenerateCreationJob) { post creations_url("image"), params: image_params }

    assert_equal 5, @user.creations.last.credits_charged
    assert_equal 5, @user.reload.credits_balance
  end

  test "an unknown image size is refused before charging" do
    post creations_url("image"), params: image_params(size: "4000x4000")

    assert_equal "Choose a size", flash[:alert]
    assert_equal 10, @user.reload.credits_balance
  end

  test "a finished image shows with a download" do
    creation = @user.creations.create!(kind: "image", model_key: "openai-gpt-image-1-mini", prompt: "A lighthouse",
                                       status: "ready", options: { "style" => "illustration", "size" => "1024x1536" })
    creation.file.attach(io: StringIO.new("\x89PNG".b), filename: "image.png", content_type: "image/png")

    get creations_url("image")

    assert_select "img[alt=?]", "A lighthouse"
    assert_select "a", text: "Download PNG"
    assert_match "Painted illustration · Portrait", response.body
  end
end
