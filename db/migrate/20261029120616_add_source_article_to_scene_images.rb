class AddSourceArticleToSceneImages < ActiveRecord::Migration[8.1]
  def change
    add_column :scene_images, :source_article, :string
  end
end
