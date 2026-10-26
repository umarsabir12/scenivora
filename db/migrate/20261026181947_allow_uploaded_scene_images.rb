class AllowUploadedSceneImages < ActiveRecord::Migration[8.0]
  def change
    # Uploaded images live in Active Storage, so they have no remote image URL.
    change_column_null :scene_images, :image_url, true
  end
end
