class AddMusicFieldsToAudioTracks < ActiveRecord::Migration[8.0]
  def change
    change_table :audio_tracks, bulk: true do |t|
      t.integer :volume, null: false, default: 18 # percent of full volume, for background music
      t.string :title
      t.string :credit
      t.string :license
      t.string :source_url # where the track was downloaded from (Commons) or nil for uploads
      t.string :page_url
    end
  end
end
