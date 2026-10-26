class AddPlanToScenes < ActiveRecord::Migration[8.0]
  def change
    add_column :scenes, :plan, :jsonb, null: false, default: {}
  end
end
