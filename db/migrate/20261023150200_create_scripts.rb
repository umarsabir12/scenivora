class CreateScripts < ActiveRecord::Migration[8.0]
  def change
    create_table :scripts do |t|
      t.references :project, null: false, foreign_key: true
      t.text :body, null: false, default: ""
      t.integer :version, null: false

      t.timestamps
    end

    add_index :scripts, [ :project_id, :version ], unique: true
  end
end
