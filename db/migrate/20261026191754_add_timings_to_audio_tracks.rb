class AddTimingsToAudioTracks < ActiveRecord::Migration[8.0]
  def change
    # Measured timing of each narration part: [{ "text", "start_ms", "end_ms" }], one part per paragraph.
    add_column :audio_tracks, :timings, :jsonb, null: false, default: []
  end
end
