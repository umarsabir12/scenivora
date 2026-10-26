module VoicesHelper
  # Where a voice sample plays from: a shipped file first, then a generated one. Nil if neither exists.
  def voice_sample_source(voice_name, sample)
    VoiceSample.static_url(voice_name) || (rails_blob_path(sample.file, disposition: "inline") if sample&.file&.attached?)
  end

  # Estimated cost of narrating this script with the default speech model.
  def voice_cost_estimate(script)
    return "—" unless script

    rate = Ai::SpeechGenerator::PRICE_PER_MILLION_CHARACTERS.fetch(Ai::SpeechGenerator::DEFAULT_MODEL, 0)
    cost = script.body.length * rate / 1_000_000.0
    format("~$%.2f (%s characters)", cost, number_with_delimiter(script.body.length))
  end

  def duration_label(milliseconds)
    total_seconds = (milliseconds / 1000.0).round
    format("%d:%02d", total_seconds / 60, total_seconds % 60)
  end
end
