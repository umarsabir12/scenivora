# One short, pre-rendered sample per voice. Generated the first time it is played, then reused.
class VoiceSample < ApplicationRecord
  SAMPLE_TEXT = "Welcome to the story. Let's see where it takes us.".freeze

  # Pre-rendered samples shipped with the app. Generated once with `bin/rails voice_samples:generate`.
  STATIC_DIR = Rails.root.join("public", "voice_samples")

  has_one_attached :file

  validates :voice_name, presence: true, uniqueness: true, inclusion: { in: Ai::SpeechGenerator::VOICES.keys }

  def self.static_url(voice_name)
    "/voice_samples/#{voice_name}.mp3" if STATIC_DIR.join("#{voice_name}.mp3").exist?
  end

  def self.generate_for(voice_name, generator: Ai::SpeechGenerator.new)
    sample = find_or_initialize_by(voice_name: voice_name)
    return sample if sample.file.attached?

    result = generator.call(text: SAMPLE_TEXT, voice: voice_name)
    sample.file.attach(io: StringIO.new(result.audio), filename: "#{voice_name}-sample.mp3", content_type: "audio/mpeg")
    sample.save!
    sample
  end
end
