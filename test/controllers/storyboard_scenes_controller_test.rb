require "test_helper"

class StoryboardScenesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "Prince Philip's escape", tone: "dramatic", target_length_minutes: 3,
                                      settings: { "storyboard" => true })
    @project.scripts.create!(body: "HMS Calypso reached Corfu.\n\nThe family sailed for Brindisi.\n\nThey settled near Paris.", version: 1)
    @project.script_ready!
    @scenes = [ "HMS Calypso reached Corfu.", "The family sailed for Brindisi.", "They settled near Paris." ].each_with_index.map do |text, index|
      @project.scenes.create!(position: index + 1, text: text, start_ms: index * 2_000, duration_ms: 2_000)
    end
    sign_in @user
  end

  test "editing a scene's narration updates the script" do
    patch scene_url(@scenes[1]), params: { scene: { text: "On 4 December 1922 the family sailed for Brindisi." } }

    assert_redirected_to project_scenes_url(@project, scene: @scenes[1].id)
    assert_equal "On 4 December 1922 the family sailed for Brindisi.", @scenes[1].reload.text
    assert_includes @project.latest_script.reload.body, "\n\nOn 4 December 1922 the family sailed for Brindisi.\n\n"
  end

  test "empty narration is refused" do
    patch scene_url(@scenes[0]), params: { scene: { text: "  " } }

    assert_equal "HMS Calypso reached Corfu.", @scenes[0].reload.text
    assert_match "between 1 and", flash[:alert]
  end

  test "deleting a scene renumbers the rest and removes its narration from the script" do
    delete scene_url(@scenes[0])

    assert_redirected_to project_scenes_url(@project)
    assert_equal [ [ 1, "The family sailed for Brindisi." ], [ 2, "They settled near Paris." ] ],
                 @project.scenes.reload.map { |scene| [ scene.position, scene.text ] }
    assert_equal "The family sailed for Brindisi.\n\nThey settled near Paris.", @project.latest_script.reload.body
  end

  test "the last scene can't be deleted" do
    @scenes[1..].each(&:destroy!)

    delete scene_url(@scenes[0])

    assert @scenes[0].reload.persisted?
    assert_equal "A video needs at least one scene.", flash[:alert]
  end

  test "nothing can be edited while the storyboard is being made" do
    @project.update!(settings: @project.settings.merge("production" => { "step" => "pictures" }))

    patch scene_url(@scenes[0]), params: { scene: { text: "Changed." } }

    assert_equal "HMS Calypso reached Corfu.", @scenes[0].reload.text
  end

  test "another user's scene is not found" do
    sign_out @user
    sign_in users(:two)

    patch scene_url(@scenes[0]), params: { scene: { text: "Changed." } }

    assert_response :not_found
  end
end
