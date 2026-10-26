class AddAiStatusToScenes < ActiveRecord::Migration[8.0]
  def change
    # nil when idle, "generating" while an AI image is being made, "failed" after an error.
    add_column :scenes, :ai_status, :string
    add_column :scenes, :ai_error, :text
  end
end
