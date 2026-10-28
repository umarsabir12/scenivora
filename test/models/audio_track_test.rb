require "test_helper"

class AudioTrackTest < ActiveSupport::TestCase
  setup do
    @project = users(:one).projects.create!(prompt: "Why bridges sway", tone: "documentary", target_length_minutes: 4)
  end

  def voice_track(**attrs)
    @project.audio_tracks.build({ kind: "voice", voice_name: "alloy", speed: 1.0 }.merge(attrs))
  end

  test "is valid with a known voice and speed in range" do
    assert voice_track.valid?
  end

  test "rejects an unknown voice" do
    track = voice_track(voice_name: "nobody")

    assert_not track.valid?
    assert track.errors[:voice_name].any?
  end

  test "rejects speeds outside 0.85x to 1.15x" do
    assert_not voice_track(speed: 0.5).valid?
    assert_not voice_track(speed: 1.5).valid?
    assert voice_track(speed: 0.85).valid?
    assert voice_track(speed: 1.15).valid?
  end

  test "music tracks do not need a voice, but need a title and a volume up to 50%" do
    track = @project.audio_tracks.build(kind: "music", speed: 1.0, title: "Calm piano")

    assert track.valid?
    track.volume = 80
    assert_not track.valid?
    track.title = ""
    assert_not track.valid?
  end

  test "a music file must be audio" do
    track = @project.audio_tracks.build(kind: "music", title: "Notes")
    track.file.attach(io: StringIO.new("not audio"), filename: "notes.txt", content_type: "text/plain")

    assert_not track.valid?
    assert track.errors[:file].any?
  end

  test "a ready track must have its audio attached" do
    track = voice_track(status: "ready")

    assert_not track.valid?
    assert track.errors[:file].any?
  end

  test "defaults to pending" do
    assert voice_track.pending?
  end

  test "the project has at most one voice track" do
    voice_track.save!

    assert_equal @project.audio_tracks.voice.first, @project.reload.voice_track
    duplicate = @project.audio_tracks.build(kind: "voice", voice_name: "echo", speed: 1.0)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "is stale when the script has changed since it was generated" do
    script = @project.scripts.create!(body: "First version of the narration.", version: 1)
    track = voice_track(status: "ready", script_digest: script.digest)
    track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
    track.save!

    assert_not track.stale_for?(script)

    script.update!(body: "Edited narration.")
    assert track.stale_for?(script.reload)
  end
end
