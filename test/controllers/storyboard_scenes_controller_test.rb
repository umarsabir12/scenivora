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

  test "the page's autosave gets every scene's new start time back" do
    patch scene_url(@scenes[0], format: :json), params: { scene: { text: "HMS Calypso, a British cruiser, reached Corfu in December 1922 to take the family away." } },
                                                as: :json

    assert_response :success
    answer = response.parsed_body
    assert_equal "0:00", answer["starts"][@scenes[0].id.to_s]
    assert_equal "0:06", answer["starts"][@scenes[1].id.to_s], "the next scene starts after the longer first one"
    assert_equal @project.scenes.reload.last.end_ms / 1000, answer["length"].split(":").then { |m, sec| m.to_i * 60 + sec.to_i }
  end

  test "narration may be emptied while it is written, and leaves the script" do
    patch scene_url(@scenes[1], format: :json), params: { scene: { text: "  " } }, as: :json

    assert_response :success
    assert_equal "", @scenes[1].reload.text
    assert_equal "HMS Calypso reached Corfu.\n\nThey settled near Paris.", @project.latest_script.reload.body
  end

  test "narration over the limit is refused" do
    patch scene_url(@scenes[0], format: :json), params: { scene: { text: "word " * 300 } }, as: :json

    assert_response :unprocessable_content
    assert_match "at most", response.parsed_body["error"]
    assert_equal "HMS Calypso reached Corfu.", @scenes[0].reload.text
  end

  test "adding a scene puts an empty one right after, and moves the later scenes down" do
    post add_after_scene_url(@scenes[0]), headers: { "Referer" => project_scenes_url(@project, scene: @scenes[2].id) }

    scenes = @project.scenes.reload
    added = scenes.second
    assert_redirected_to project_scenes_url(@project, scene: @scenes[2].id), "back to the same address, so the page keeps its scroll"
    assert_equal added.id, flash[:new_scene_id]
    assert_equal [ "HMS Calypso reached Corfu.", "", "The family sailed for Brindisi.", "They settled near Paris." ], scenes.map(&:text)
    assert_equal [ 1, 2, 3, 4 ], scenes.map(&:position)
    assert_equal scenes.first.end_ms, added.start_ms
    assert_equal added.end_ms, scenes.third.start_ms
  end

  test "without a storyboard address to go back to, adding a scene goes to the storyboard" do
    post add_after_scene_url(@scenes[0]), headers: { "Referer" => "https://evil.example/" }

    assert_redirected_to project_scenes_url(@project)
  end

  test "a scene can be added after the last one" do
    post add_after_scene_url(@scenes[2])

    assert_equal [ 4, "" ], @project.scenes.reload.last.then { |scene| [ scene.position, scene.text ] }
  end

  test "an older project's scenes can't be edited here" do
    @project.update!(settings: {})

    post add_after_scene_url(@scenes[0])

    assert_equal 3, @project.scenes.count
    assert_match "storyboard", flash[:alert]
  end

  test "deleting a scene renumbers the rest and removes its narration from the script" do
    delete scene_url(@scenes[0]), headers: { "Referer" => project_scenes_url(@project, scene: @scenes[0].id) }

    assert_redirected_to project_scenes_url(@project, scene: @scenes[0].id), "back to the same address; the page opens another scene"
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
