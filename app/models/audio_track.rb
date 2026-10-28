class AudioTrack < ApplicationRecord
  MUSIC_TYPES = %w[audio/mpeg audio/mp4 audio/x-m4a audio/aac audio/wav audio/x-wav audio/vnd.wave
                   audio/ogg application/ogg audio/flac audio/x-flac audio/webm].freeze
  MAX_MUSIC_BYTES = 40.megabytes
  MAX_MUSIC_VOLUME = 50

  belongs_to :project
  has_one_attached :file

  enum :kind, { voice: "voice", music: "music" }, validate: true
  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" },
    default: "pending", validate: true

  validates :voice_name, inclusion: { in: Ai::SpeechGenerator::VOICES.keys }, if: :voice?
  validates :speed, numericality: { greater_than_or_equal_to: 0.85, less_than_or_equal_to: 1.15 }, if: :voice?
  validates :duration_ms, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :volume, numericality: { only_integer: true, in: 0..MAX_MUSIC_VOLUME }, if: :music?
  validates :title, presence: true, if: :music?
  validate :file_attached_when_ready
  validate :acceptable_music_file, if: -> { music? && file.attached? }

  def confirmed?
    confirmed_at.present?
  end

  # True when the script was edited after this track was generated.
  def stale_for?(script)
    ready? && script.present? && script_digest != script.digest
  end

  private
    def acceptable_music_file
      errors.add(:file, "must be an MP3, M4A, WAV, OGG or FLAC file") unless MUSIC_TYPES.include?(file.content_type)
      errors.add(:file, "must be smaller than 40 MB") if file.byte_size > MAX_MUSIC_BYTES
    end

    def file_attached_when_ready
      errors.add(:file, "must be attached before the track is ready") if ready? && !file.attached?
    end
end
