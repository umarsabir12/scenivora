class AddRenderAndPublishFieldsToProjects < ActiveRecord::Migration[8.0]
  def change
    change_table :projects, bulk: true do |t|
      t.text :render_error
      t.string :yt_title
      t.text :yt_description
      t.string :yt_tags, array: true, null: false, default: []
      t.string :yt_category
    end
  end
end
