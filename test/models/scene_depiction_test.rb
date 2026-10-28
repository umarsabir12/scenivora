require "test_helper"

class SceneDepictionTest < ActiveSupport::TestCase
  setup do
    @project = users(:one).projects.create!(prompt: "Khalid ibn al-Walid", tone: "documentary", target_length_minutes: 3)
  end

  def scene(plan)
    @project.scenes.create!(position: @project.scenes.count + 1, text: "x", start_ms: 0, duration_ms: 10_000, plan: plan)
  end

  test "revered figures use their depiction rule for AI images" do
    assert_equal "no_face", scene("depiction" => "no_face", "ai_fallback_allowed" => false).ai_style
    assert_equal "no_figure", scene("depiction" => "no_figure").ai_style
  end

  test "other real people are painted illustrations and everything else is a photo" do
    assert_equal "illustration", scene("depiction" => "normal", "ai_fallback_allowed" => false).ai_style
    assert_equal "photo", scene({}).ai_style
  end

  test "an unknown depiction is treated as normal" do
    assert_equal "normal", scene("depiction" => "cartoon").depiction
  end

  test "the whole video's rule applies to every scene, but a scene can be stricter" do
    @project.update!(settings: { "topic_depiction" => "no_face" })

    assert_equal "no_face", scene({}).depiction
    assert_equal "no_figure", scene("depiction" => "no_figure").depiction
  end
end
