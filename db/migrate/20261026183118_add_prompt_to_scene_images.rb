class AddPromptToSceneImages < ActiveRecord::Migration[8.0]
  def change
    add_column :scene_images, :prompt, :text
  end
end
