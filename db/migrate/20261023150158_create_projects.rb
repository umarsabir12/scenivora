class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :prompt
      t.string :tone
      t.integer :target_length_minutes
      t.string :status, null: false, default: "draft"
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :projects, [ :user_id, :created_at ]
  end
end
