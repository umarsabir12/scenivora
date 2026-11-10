# One thing a user made with a single tool (Create video, image, speech or text), outside any
# YouTube project. Credits are charged when it's asked for and refunded if it fails.
class Creation < ApplicationRecord
  MAX_SPEECH_CHARACTERS = 10_000
  SPEED_RANGE = (0.75..1.25).freeze

  belongs_to :user
  has_many :api_usages, dependent: :nullify
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" }, validate: true

  validates :kind, inclusion: { in: CreationModels::KINDS }
  validates :prompt, presence: true
  validates :prompt, length: { maximum: MAX_SPEECH_CHARACTERS }, if: -> { kind == "speech" }
  validate :known_model
  validate :speech_options, if: -> { kind == "speech" }

  scope :recent, -> { order(created_at: :desc) }

  def model
    CreationModels.find(kind, model_key)
  end

  def voice = options["voice"]
  def speed = options["speed"].to_f

  # Charges the user and queues the work. Raises User::InsufficientCredits when the balance is too low.
  def self.start!(user, attributes)
    creation = user.creations.build(attributes)
    creation.credits_charged = creation.model ? CreationModels.credits_for(creation.model, creation.prompt) : 0
    return creation unless creation.valid?

    transaction do
      user.charge_credits!(creation.credits_charged, reason: "create_#{creation.kind}") if creation.credits_charged.positive?
      creation.save!
    end
    GenerateCreationJob.perform_later(creation)
    creation
  end

  private
    def known_model
      errors.add(:model_key, "isn't offered for this tool") unless model
    end

    def speech_options
      errors.add(:base, "Choose a voice") unless Ai::SpeechGenerator::VOICES.key?(voice)
      errors.add(:base, "Speed must be between #{SPEED_RANGE.min} and #{SPEED_RANGE.max}") unless SPEED_RANGE.cover?(speed)
    end
end
