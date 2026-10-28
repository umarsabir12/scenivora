require "test_helper"

class VideoDescriptionTest < ActiveSupport::TestCase
  setup do
    @project = project_with_approved_scenes
  end

  test "lists AI disclosures, credits for sourced images, and the music credit" do
    ready_music_track(@project)

    footer = VideoDescription.new(@project.reload).footer

    assert_includes footer, "Narration is AI-generated."
    assert_includes footer, "Image credits:\n- Jane, CC BY 4.0, https://commons.wikimedia.org/wiki/File:A.jpg"
    assert_not_includes footer, "Your upload"
    assert_includes footer, "Music: Calm piano, Kim, CC BY 4.0, https://commons.wikimedia.org/wiki/File:Calm.ogg"
    assert_not_includes footer, "Some images are AI-generated."
  end

  test "mentions AI images only when an AI image is selected" do
    scene = @project.scenes.first
    ai = scene.images.build(provider: "ai", credit: "AI generated", license: "AI generated")
    ai.file.attach(io: StringIO.new("png"), filename: "ai.png", content_type: "image/png")
    ai.save!
    ai.select!

    assert_includes VideoDescription.new(@project.reload).footer, "Some images are AI-generated."
  end

  test "puts the footer under the written description" do
    full = VideoDescription.new(@project).full("A story about the sea.")

    assert full.start_with?("A story about the sea.\n\nNarration is AI-generated.")
  end
end
