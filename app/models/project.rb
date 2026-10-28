class Project < ApplicationRecord
  TONES = %w[documentary dramatic inspirational casual].freeze
  TARGET_LENGTH_MINUTES = (3..10).freeze
  WORDS_PER_MINUTE = 150
  SCENES_APPROVED_STATUSES = %w[scenes_ready media_ready rendering rendered].freeze
  MEDIA_READY_STATUSES = %w[media_ready rendering rendered].freeze

  belongs_to :user
  has_many :scripts, -> { order(:version) }, dependent: :destroy, inverse_of: :project
  has_many :api_usages, dependent: :destroy
  has_many :audio_tracks, dependent: :destroy
  has_many :credit_transactions, dependent: :nullify
  has_many :scenes, -> { order(:position) }, dependent: :destroy
  has_one :voice_track, -> { voice }, class_name: "AudioTrack", dependent: :destroy, inverse_of: :project
  has_one :music_track, -> { music }, class_name: "AudioTrack", dependent: :destroy, inverse_of: :project
  has_one_attached :video
  has_one_attached :thumbnail

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
  validates :yt_title, length: { maximum: Ai::MetadataGenerator::MAX_TITLE }
  validates :yt_description, length: { maximum: 5_000 }
  validates :yt_category, inclusion: { in: Ai::MetadataGenerator::CATEGORIES }, allow_blank: true

  def latest_script
    scripts.last
  end

  def next_script_version
    (scripts.maximum(:version) || 0) + 1
  end

  IMAGE_MODES = %w[real_first ai_all].freeze

  # "real_first" (default): checked real pictures, AI suggested where none fits. "ai_all": AI for every scene.
  def image_mode
    settings["image_mode"].presence_in(IMAGE_MODES) || "real_first"
  end

  # Captions are burned into the video unless the user turned them off.
  def captions_enabled?
    settings["captions"] != false
  end

  def scenes_approved?
    SCENES_APPROVED_STATUSES.include?(status)
  end

  def media_approved?
    MEDIA_READY_STATUSES.include?(status)
  end

  # Any status past draft has a script, so the Voice step stays reachable in later steps too.
  def voice_available?
    !draft?
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
