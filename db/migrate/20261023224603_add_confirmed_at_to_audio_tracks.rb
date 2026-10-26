class AddConfirmedAtToAudioTracks < ActiveRecord::Migration[8.0]
  def change
    add_column :audio_tracks, :confirmed_at, :datetime
  end
end
