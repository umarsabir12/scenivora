class AudioTrack < ApplicationRecord
  belongs_to :project
  has_one_attached :file

  enum :kind, { voice: "voice", music: "music" }, validate: true
  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" },
    default: "pending", validate: true

  validates :voice_name, inclusion: { in: Ai::SpeechGenerator::VOICES.keys }, if: :voice?
  validates :speed, numericality: { greater_than_or_equal_to: 0.85, less_than_or_equal_to: 1.15 }, if: :voice?
  validates :duration_ms, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :file_attached_when_ready

  def confirmed?
    confirmed_at.present?
  end

  # True when the script was edited after this track was generated.
  def stale_for?(script)
    ready? && script.present? && script_digest != script.digest
  end

  private
    def file_attached_when_ready
      errors.add(:file, "must be attached before the track is ready") if ready? && !file.attached?
    end
end
