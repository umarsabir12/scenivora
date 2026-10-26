class CreateSceneImages < ActiveRecord::Migration[8.0]
  def change
    create_table :scene_images do |t|
      t.references :scene, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :image_url, null: false
      t.string :page_url
      t.string :credit
      t.string :license
      t.boolean :selected, null: false, default: false

      t.timestamps
    end
  end
end
