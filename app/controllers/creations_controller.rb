# The single tools in the sidebar's Create group: a form for one kind of thing (video, image,
# speech, text) with a model picker, and the user's past results of that kind.
class CreationsController < ApplicationController
  TITLES = { "video" => "Create video", "image" => "Create image", "speech" => "Text to speech", "text" => "Write text" }.freeze
  # Tools with a form so far; the others say "Models coming soon".
  FORMS = %w[speech image].freeze
  DEFAULT_OPTIONS = {
    "speech" => { "voice" => Ai::SpeechGenerator::VOICES.keys.first, "speed" => 1.0 },
    "image" => { "style" => "photo", "size" => "1536x1024" }
  }.freeze

  before_action :set_kind

  def index
    @models = CreationModels.for(@kind)
    @creation = current_user.creations.build(kind: @kind, model_key: @models.first&.key, options: DEFAULT_OPTIONS.fetch(@kind, {}))
    @creations = current_user.creations.where(kind: @kind).recent.limit(20).with_attached_file
    @samples = VoiceSample.where(voice_name: Ai::SpeechGenerator::VOICES.keys).index_by(&:voice_name) if @kind == "speech"
  end

  def create
    creation = Creation.start!(current_user, creation_params.merge(kind: @kind))
    if creation.persisted?
      redirect_to creations_path(@kind), notice: "Working on it. #{helpers.pluralize(creation.credits_charged, "credit")} charged."
    else
      redirect_to creations_path(@kind), alert: creation.errors.full_messages.to_sentence
    end
  rescue User::InsufficientCredits
    redirect_to creations_path(@kind), alert: "You don't have enough credits for this. You have #{current_user.reload.credits_balance}."
  end

  private
    def set_kind
      @kind = params[:kind]
      @title = TITLES.fetch(@kind)
    end

    def creation_params
      permitted = params.expect(creation: [ :model_key, :prompt, { options: %i[voice speed style size] } ])
      permitted[:options] = permitted[:options].to_h if permitted[:options]
      permitted
    end
end
