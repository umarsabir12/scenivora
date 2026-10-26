class CreateAudioTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :audio_tracks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :voice_name
      t.decimal :speed, precision: 3, scale: 2, null: false, default: 1.0
      t.integer :duration_ms
      t.string :status, null: false, default: "pending"
      t.text :error
      t.string :script_digest

      t.timestamps
    end

    add_index :audio_tracks, [ :project_id, :kind ], unique: true
  end
end
