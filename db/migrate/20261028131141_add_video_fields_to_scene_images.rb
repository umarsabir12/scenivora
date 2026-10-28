class AddVideoFieldsToSceneImages < ActiveRecord::Migration[8.1]
  def change
    change_table :scene_images, bulk: true do |t|
      t.string :media_type, null: false, default: "image" # "image" or "video"
      t.string :poster_url # still frame shown for a video candidate
      t.integer :duration_ms # length of the source video
      t.integer :clip_start_ms # where in the source video the scene's clip starts
    end
  end
end
