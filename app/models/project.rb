class Project < ApplicationRecord
  TONES = %w[documentary dramatic inspirational casual].freeze
  # What each category asks of the research and the script.
  CATEGORIES = {
    "history" => "Events in order, with dates, places and the people involved.",
    "biography" => "One person's life: origins, turning points and achievements, with dates and places.",
    "religion" => "Respectful and accurate. Attribute traditions to their sources and follow the depiction rules for revered figures.",
    "war" => "Campaigns, battles, commanders, ships and places, with dates. No graphic violence.",
    "science" => "Discoveries, the people and instruments behind them, and clear explanations.",
    "mysteries" => "Separate established facts from theories, and say who claims what.",
    "nature" => "Animals, landscapes and natural events: where, when and at what scale.",
    "places" => "Cities, buildings and landscapes: their history, landmarks and what they look like.",
    "sports" => "Players, clubs, matches and careers, with dates, places and results. Say who told each personal story."
  }.freeze
  MAX_INSTRUCTIONS = 1_000
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
  validates :category, inclusion: { in: CATEGORIES.keys }, allow_blank: true
  validates :instructions, length: { maximum: MAX_INSTRUCTIONS }
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

  # In a storyboard project the steps run storyboard (script_ready) -> approved (scenes_ready) ->
  # voice confirmed (voice_ready) -> music (media_ready). Older projects ran script -> voice -> scenes.
  STORYBOARD_APPROVED_STATUSES = %w[scenes_ready voice_ready media_ready rendering rendered].freeze
  VOICE_CONFIRMED_STATUSES = %w[voice_ready media_ready rendering rendered].freeze

  def scenes_approved?
    SCENES_APPROVED_STATUSES.include?(status)
  end

  def storyboard_approved?
    storyboard? ? STORYBOARD_APPROVED_STATUSES.include?(status) : scenes_approved?
  end

  # The music step opens once the storyboard's voice is confirmed (older projects: once scenes are approved).
  def music_available?
    storyboard? ? VOICE_CONFIRMED_STATUSES.include?(status) : scenes_approved?
  end

  def media_approved?
    MEDIA_READY_STATUSES.include?(status)
  end

  # A storyboard gets its voice once approved. In older projects any status past draft has a
  # script, so the Voice step stays reachable in later steps too.
  def voice_available?
    storyboard? ? storyboard_approved? : !draft?
  end

  # A storyboard's narration is voiced one paragraph (scene) at a time, so each scene takes its part's
  # measured time. If the parts don't match the scenes one to one (a scene too long for one voice
  # call), the estimated times are scaled to the voice's length instead.
  def time_scenes_from_voice!
    track = voice_track
    timings = Array(track&.timings)
    list = scenes.reload.to_a
    return if list.empty? || track&.duration_ms.to_i.zero?

    transaction do
      if timings.size == list.size
        list.zip(timings).each { |scene, timing| scene.update!(start_ms: timing["start_ms"], duration_ms: timing["end_ms"] - timing["start_ms"]) }
      else
        scale = track.duration_ms.to_f / list.sum(&:duration_ms)
        start_ms = 0
        list.each_with_index do |scene, index|
          duration = index == list.size - 1 ? track.duration_ms - start_ms : (scene.duration_ms * scale).round
          scene.update!(start_ms: start_ms, duration_ms: duration)
          start_ms += duration
        end
      end
    end
  end

  # After a storyboard edit: the script follows the scenes, scene times are estimated again, and the
  # voice (now out of date) must be made again, so the project goes back to the storyboard step.
  def storyboard_changed!
    texts = scenes.reload.map(&:text)
    transaction do
      latest_script.update!(body: StoryboardScenes.script_for(texts))
      start_ms = 0
      scenes.each.with_index(1) do |scene, position|
        duration = StoryboardScenes.estimated_ms(scene.text)
        scene.update!(position: position, start_ms: start_ms, duration_ms: duration)
        start_ms += duration
      end
      voice_track&.update!(confirmed_at: nil)
      update!(status: :script_ready) if storyboard_approved?
    end
  end

  # Made with "Create video": the scenes are laid out from the script, before the voice.
  def storyboard?
    settings["storyboard"] == true
  end

  PRODUCTION_STEPS = %w[writing pictures ai_images].freeze

  def production_step
    settings.dig("production", "step")
  end

  # True while "Create video" is still researching, writing or finding pictures.
  def producing?
    PRODUCTION_STEPS.include?(production_step)
  end

  # Starts "Create video" (or a rewrite of the whole storyboard). No-op while a run is in progress.
  def start_production!
    return if producing?

    update!(status: :draft, settings: settings.merge("production" => { "step" => "writing" }))
    ProduceVideoJob.perform_later(self)
  end

  def target_word_count
    target_length_minutes * WORDS_PER_MINUTE
  end

  private
    def default_title_from_prompt
      self.title = prompt.to_s.squish.truncate(80) if title.blank?
    end
end
