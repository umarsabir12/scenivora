# Single tools (Create video, image, speech, text): one row per thing a user made, outside any
# YouTube project. Their API cost is recorded in api_usages against the creation instead of a project.
class CreateCreations < ActiveRecord::Migration[8.1]
  def change
    create_table :creations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :model_key, null: false
      t.text :prompt, null: false
      t.jsonb :options, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.string :error
      t.integer :credits_charged, null: false, default: 0
      t.integer :duration_ms
      t.timestamps
    end
    add_index :creations, [ :user_id, :kind, :created_at ]

    change_column_null :api_usages, :project_id, true
    add_reference :api_usages, :creation, foreign_key: true
  end
end
