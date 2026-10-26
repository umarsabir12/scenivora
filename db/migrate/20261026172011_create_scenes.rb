class CreateScenes < ActiveRecord::Migration[8.0]
  def change
    create_table :scenes do |t|
      t.references :project, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :text, null: false
      t.integer :start_ms, null: false
      t.integer :duration_ms, null: false
      t.string :search_query
      t.text :search_error

      t.timestamps
    end

    add_index :scenes, [ :project_id, :position ], unique: true
  end
end
