class Scene < ApplicationRecord
  belongs_to :project
  has_many :images, -> { order(:id) }, class_name: "SceneImage", dependent: :destroy

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :project_id }
  validates :text, presence: true
  validates :start_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :duration_ms, numericality: { only_integer: true, greater_than: 0 }

  STOPWORDS = %w[the and for with that this from into over under about after before were was are is
                 its their they them your you our his her she him not but also just than then when where
                 which while what who whom have has had been being will would could should can may might
                 one two more most some such each every many much very even only still here there
                 he she it we they i in on at of to a an as by be do did if so no].freeze

  def end_ms
    start_ms + duration_ms
  end

  # The planner marks scenes that show a real person. Their AI images are painted illustrations,
  # never photorealistic, so they can't be mistaken for real photographs of that person.
  def ai_style
    plan.fetch("ai_fallback_allowed", true) == false ? "illustration" : "photo"
  end

  def ai_generating?
    ai_status == "generating"
  end

  def ai_suggested?
    media_check == "ai_suggested"
  end

  # The prompt an AI image starts from: the planner's description of what the viewer should see.
  def suggested_ai_prompt
    plan["visual_intent"].presence || text
  end

  # Charges the user and queues an AI image. Returns false when one is already being generated.
  # Raises User::InsufficientCredits when the balance is too low.
  def start_ai_image!(user, prompt)
    cost = CreditPricing.ai_image
    started = Scene.transaction do
      lock!
      next false if ai_generating?

      user.charge_credits!(cost, reason: "ai_image", project: project)
      update!(ai_status: "generating", ai_error: nil)
      true
    end
    GenerateSceneImageJob.perform_later(self, prompt, cost) if started
    started
  end

  def selected_image
    images.find(&:selected?)
  end

  # Search words: capitalised names first, then the longest other words. Crude, until the planner exists.
  def self.query_for(text)
    words = text.scan(/[A-Za-z][A-Za-z'-]+/).reject { |w| STOPWORDS.include?(w.downcase) }
    proper = words.select { |w| w.match?(/\A[A-Z]/) }
    others = (words - proper).sort_by { |w| -w.length }
    (proper + others).uniq(&:downcase).first(4).join(" ")
  end
end
