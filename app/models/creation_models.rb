# The models each single tool offers, read from config/creation_models.yml.
module CreationModels
  KINDS = %w[video image speech text].freeze

  Model = Data.define(:key, :name, :provider, :model, :price, :credits_per_1000_characters, :credits_per_image) do
    # For the model picker, e.g. "1 credit per 1,000 characters".
    def credit_label
      if credits_per_1000_characters
        "#{credits_per_1000_characters} #{"credit".pluralize(credits_per_1000_characters)} per 1,000 characters"
      elsif credits_per_image
        "#{credits_per_image} #{"credit".pluralize(credits_per_image)} per image"
      end
    end
  end

  def self.for(kind)
    Array(config[kind]).map do |entry|
      Model.new(**Model.members.index_with { |member| entry[member.to_s] })
    end
  end

  def self.find(kind, key)
    self.for(kind).find { |model| model.key == key }
  end

  # Credits for one creation: speech per started 1,000 characters, images per image.
  def self.credits_for(model, prompt)
    if model.credits_per_1000_characters
      (prompt.to_s.length / 1000.0).ceil * model.credits_per_1000_characters
    else
      model.credits_per_image.to_i
    end
  end

  def self.config
    @config ||= YAML.load_file(Rails.root.join("config/creation_models.yml"))
  end
end
