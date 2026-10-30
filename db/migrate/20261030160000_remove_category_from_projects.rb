class RemoveCategoryFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :category, :string
  end
end
