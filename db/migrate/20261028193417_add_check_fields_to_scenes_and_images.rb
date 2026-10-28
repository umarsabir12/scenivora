class AddCheckFieldsToScenesAndImages < ActiveRecord::Migration[8.1]
  def change
    # What Wikimedia says about a file, so the relevance check can judge more than its title.
    change_table :scene_images, bulk: true do |t|
      t.text :description
      t.string :taken_on
      t.text :categories
    end

    # The outcome of the picture check: "verified" (a checked real picture is selected),
    # "ai_suggested" (nothing real fits, an AI image is suggested), or nil (not checked).
    change_table :scenes, bulk: true do |t|
      t.string :media_check
      t.text :media_note
    end
  end
end
