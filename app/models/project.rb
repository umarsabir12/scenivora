class Project < ApplicationRecord
  TONES = %w[documentary dramatic inspirational casual].freeze
  TARGET_LENGTH_MINUTES = (3..10).freeze
  WORDS_PER_MINUTE = 150

  belongs_to :user
  has_many :scripts, -> { order(:version) }, dependent: :destroy, inverse_of: :project
  has_many :api_usages, dependent: :destroy
  has_many :audio_tracks, dependent: :destroy
  has_one :voice_track, -> { voice }, class_name: "AudioTrack", dependent: :destroy, inverse_of: :project

  enum :status, {
    draft: "draft",
    script_ready: "script_ready",
    voice_ready: "voice_ready",
    scenes_ready: "scenes_ready",
    media_ready: "media_ready",
    rendering: "rendering",
    rendered: "rendered"
  }, default: "draft", validate: true

  before_validation :default_title_from_prompt

  validates :title, presence: true, length: { maximum: 120 }
  validates :prompt, presence: true, length: { maximum: 2_000 }
  validates :tone, inclusion: { in: TONES }
  validates :target_length_minutes, numericality: { only_integer: true, in: TARGET_LENGTH_MINUTES }

  def latest_script
    scripts.last
  end

  def next_script_version
    (scripts.maximum(:version) || 0) + 1
  end

  def voice_available?
    script_ready? || voice_ready?
  end

  def script_generating?
    settings["script_generating"] == true
  end

  # Marks the project as generating and enqueues the job. No-op if a run is already in progress.
  def start_script_generation!
    return if script_generating?

    update!(settings: settings.merge("script_generating" => true))
    GenerateScriptJob.perform_later(self)
  end

  def target_word_count
    target_length_minutes * WORDS_PER_MINUTE
  end

  private
    def default_title_from_prompt
      self.title = prompt.to_s.squish.truncate(80) if title.blank?
    end
end
