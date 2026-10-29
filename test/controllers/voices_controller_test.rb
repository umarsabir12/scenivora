require "test_helper"

class VoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "Why glaciers carve valleys", tone: "documentary", target_length_minutes: 5)
    @project.scripts.create!(body: "A narration about glaciers.", version: 1)
    @project.script_ready!
    sign_in @user
  end

  test "the voice step is blocked until a script exists" do
    draft = @user.projects.create!(prompt: "No script yet", tone: "casual", target_length_minutes: 3)

    get project_voice_url(draft)

    assert_redirected_to project_scenes_url(draft)
    assert_equal "Approve the storyboard before choosing a voice.", flash[:alert]
  end

  test "a storyboard gets its voice only once the storyboard is approved" do
    @project.update!(settings: { "storyboard" => true })

    get project_voice_url(@project)
    assert_redirected_to project_scenes_url(@project)

    @project.scenes_ready!
    get project_voice_url(@project)
    assert_response :success
  end

  test "confirming a storyboard's voice times each scene from its part and opens music" do
    @project.update!(settings: { "storyboard" => true }, status: :scenes_ready)
    @project.latest_script.update!(body: "HMS Calypso reached Corfu.\n\nThe family sailed for Brindisi.")
    @project.scenes.create!(position: 1, text: "HMS Calypso reached Corfu.", start_ms: 0, duration_ms: 2_000)
    @project.scenes.create!(position: 2, text: "The family sailed for Brindisi.", start_ms: 2_000, duration_ms: 2_400)
    track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 5_100,
      script_digest: @project.latest_script.digest,
      timings: [ { "text" => "HMS Calypso reached Corfu.", "start_ms" => 0, "end_ms" => 2_300 },
                 { "text" => "The family sailed for Brindisi.", "start_ms" => 2_300, "end_ms" => 5_100 } ])
    track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
    track.update!(status: "ready")

    post confirm_project_voice_url(@project)

    assert_redirected_to project_music_url(@project)
    assert @project.reload.voice_ready?
    assert_equal [ [ 0, 2_300 ], [ 2_300, 2_800 ] ], @project.scenes.map { |scene| [ scene.start_ms, scene.duration_ms ] }
  end

  test "the Voice tab lists every voice with a sample control and a speed slider" do
    get project_voice_url(@project)

    assert_response :success
    Ai::SpeechGenerator::VOICES.each_key do |name|
      assert_select "input[type=radio][value=?]", name
    end
    assert_select "input[type=range][min='0.85'][max='1.15']"
    assert_select "input[type=submit][value='Generate voice']"
  end

  test "generate enqueues the voice job with the chosen voice and speed" do
    assert_enqueued_with(job: GenerateVoiceJob) do
      post project_voice_url(@project), params: { audio_track: { voice_name: "nova", speed: "1.1" } }, as: :turbo_stream
    end

    track = @project.reload.voice_track
    assert_equal "nova", track.voice_name
    assert_equal BigDecimal("1.1"), track.speed
    assert track.pending?
  end

  test "retry and regenerate reuse the stored voice when no settings are sent" do
    @project.create_voice_track!(kind: "voice", voice_name: "onyx", speed: 0.95, status: "failed", error: "boom")

    assert_enqueued_with(job: GenerateVoiceJob) do
      post project_voice_url(@project), as: :turbo_stream
    end

    track = @project.reload.voice_track
    assert_equal "onyx", track.voice_name
    assert_equal BigDecimal("0.95"), track.speed
    assert track.pending?
    assert_nil track.error
  end

  test "an unknown voice is rejected with a message instead of an error page" do
    assert_no_enqueued_jobs do
      post project_voice_url(@project), params: { audio_track: { voice_name: "nobody", speed: "1.0" } }
    end

    assert_redirected_to project_voice_url(@project)
    assert_match "Voice name is not included", flash[:alert]
  end

  test "a failed track shows its error and a Retry control" do
    @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, status: "failed", error: "Speech generation failed: rate limited")

    get project_voice_url(@project)

    assert_select "[role=alert]", text: /rate limited/
    assert_select "a", text: "Retry"
  end

  test "a ready track plays its audio and warns when the script has changed" do
    track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 65_000,
      script_digest: @project.latest_script.digest)
    track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
    track.update!(status: "ready")

    get project_voice_url(@project)
    assert_select "audio[controls]"
    assert_select "p", text: /1:05/
    assert_select "p", text: /The narration changed since this voice was made/, count: 0

    @project.latest_script.update!(body: "An edited narration.")
    get project_voice_url(@project)
    assert_select "p", text: /The narration changed since this voice was made. Regenerate the voice\?/
  end

  test "another user's project cannot be voiced" do
    other = users(:two).projects.create!(prompt: "Someone else's video", tone: "casual", target_length_minutes: 3)
    other.scripts.create!(body: "Private narration.", version: 1)
    other.script_ready!

    get project_voice_url(other)

    assert_response :not_found
  end

  test "confirming a ready voice records the confirmation" do
    track = ready_track

    post confirm_project_voice_url(@project)

    assert_redirected_to project_scenes_url(@project)
    assert track.reload.confirmed?
  end

  test "a voice cannot be confirmed while the script has changed since it was generated" do
    track = ready_track
    @project.latest_script.update!(body: "An edited narration.")

    post confirm_project_voice_url(@project)

    assert_not track.reload.confirmed?
    assert_equal "The script changed since this voice was generated. Regenerate it first.", flash[:alert]
  end

  test "nothing can be confirmed before a voice exists" do
    post confirm_project_voice_url(@project)

    assert_equal "Generate a voice before confirming it.", flash[:alert]
  end

  test "regenerating clears the earlier confirmation" do
    track = ready_track
    track.update!(confirmed_at: Time.current)

    post project_voice_url(@project), params: { audio_track: { voice_name: "echo", speed: "1.0" } }

    assert_nil track.reload.confirmed_at
  end

  private
    def ready_track
      track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 65_000,
        script_digest: @project.latest_script.digest)
      track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
      track.update!(status: "ready")
      track
    end
end
