module Media
  # One candidate music track from a free source, with what we need to play and credit it.
  AudioResult = Data.define(:provider, :title, :audio_url, :page_url, :credit, :license, :duration_ms, :content_type)
end
