class CreateApiUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :api_usages do |t|
      t.references :project, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :operation, null: false
      t.integer :units, null: false, default: 0
      t.decimal :cost_usd, precision: 10, scale: 6, null: false, default: 0

      t.timestamps
    end

    add_index :api_usages, [ :project_id, :provider ]
  end
end
