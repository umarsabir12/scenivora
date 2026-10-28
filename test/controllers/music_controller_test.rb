require "test_helper"

class MusicControllerTest < ActionDispatch::IntegrationTest
  class FakeAudioSearch
    def initialize(results: [], error: nil)
      @results = results
      @error = error
    end

    def search(_query, limit: 8)
      raise @error if @error

      @results
    end
  end

  RESULT = Media::AudioResult.new(provider: "wikimedia_commons", title: "Home Song", audio_url: "https://upload.wikimedia.org/home.wav",
                                  page_url: "https://commons.wikimedia.org/wiki/File:Home.wav", credit: "Ross",
                                  license: "CC BY 4.0", duration_ms: 185_000, content_type: "audio/wav")

  setup do
    @user = users(:one)
    @project = project_with_approved_scenes(@user)
    sign_in @user
  end

  def show_with(search)
    with_stubbed_new(Media::CommonsAudioSearch, search) { get project_music_url(@project) }
  end

  test "the music step needs approved scenes" do
    @project.update!(status: "voice_ready")

    get project_music_url(@project)

    assert_redirected_to project_scenes_url(@project)
  end

  test "lists free tracks with a preview and a button to use each one" do
    show_with(FakeAudioSearch.new(results: [ RESULT ]))

    assert_response :success
    assert_select "li", text: /Home Song/
    assert_select "audio[src=?]", "https://upload.wikimedia.org/home.wav"
    assert_select "form[action=?] input[name=audio_url][value=?]", project_music_path(@project), "https://upload.wikimedia.org/home.wav"
    assert_select "form[action=?] button", continue_project_music_path(@project), text: "Continue without music"
  end

  test "a failed music search shows a message and the page still works" do
    show_with(FakeAudioSearch.new(error: Media::Error.new("offline")))

    assert_response :success
    assert_select "[role=alert]", text: "Music search failed. Try again later."
  end

  test "choosing a Commons track creates it and queues the download" do
    assert_enqueued_with(job: PrepareMusicTrackJob) do
      post project_music_url(@project), params: { audio_url: RESULT.audio_url, title: "Home Song", credit: "Ross",
                                                  license: "CC BY 4.0", page_url: RESULT.page_url }
    end

    track = @project.reload.music_track
    assert_equal "Home Song", track.title
    assert track.pending?
  end

  test "only files from upload.wikimedia.org can be chosen" do
    assert_no_enqueued_jobs do
      post project_music_url(@project), params: { audio_url: "https://evil.example/a.mp3", title: "x" }
    end

    assert_nil @project.reload.music_track
    assert_equal "That track can't be used.", flash[:alert]
  end

  test "uploading an audio file queues it for preparation" do
    assert_enqueued_with(job: PrepareMusicTrackJob) do
      post upload_project_music_url(@project), params: { file: fixture_file_upload("tone.mp3", "audio/mpeg") }
    end

    track = @project.reload.music_track
    assert_equal "tone", track.title
    assert_equal "Your upload", track.credit
    assert track.file.attached?
  end

  test "uploading a file that isn't audio is refused" do
    assert_no_enqueued_jobs do
      post upload_project_music_url(@project), params: { file: fixture_file_upload("notes.txt", "text/plain") }
    end

    assert_match "must be an MP3", flash[:alert]
  end

  test "volume can be changed up to 50%" do
    track = ready_music_track(@project)

    patch project_music_url(@project), params: { volume: 30 }
    assert_equal 30, track.reload.volume

    patch project_music_url(@project), params: { volume: 90 }
    assert_equal 30, track.reload.volume
  end

  test "continuing without music moves the project to render" do
    post continue_project_music_url(@project)

    assert_redirected_to project_render_url(@project)
    assert @project.reload.media_ready?
  end

  test "continuing waits while a track is still being prepared" do
    @project.create_music_track!(title: "Loading", source_url: "https://upload.wikimedia.org/a.ogg")

    post continue_project_music_url(@project)

    assert_redirected_to project_music_url(@project)
    assert @project.reload.scenes_ready?
  end

  test "removing music deletes the track" do
    ready_music_track(@project)

    delete project_music_url(@project)

    assert_nil @project.reload.music_track
  end

  test "another user's project is not found" do
    other = project_with_approved_scenes(users(:two))

    get project_music_url(other)

    assert_response :not_found
  end
end
