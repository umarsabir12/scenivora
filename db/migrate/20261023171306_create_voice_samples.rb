class CreateVoiceSamples < ActiveRecord::Migration[8.0]
  def change
    create_table :voice_samples do |t|
      t.string :voice_name, null: false

      t.timestamps
    end

    add_index :voice_samples, :voice_name, unique: true
  end
end
