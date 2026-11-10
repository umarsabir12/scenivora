# The models each single tool offers, read from config/creation_models.yml.
module CreationModels
  KINDS = %w[video image speech text].freeze

  Model = Data.define(:key, :name, :provider, :model, :price, :credits_per_1000_characters)

  def self.for(kind)
    Array(config[kind]).map { |entry| Model.new(**entry.symbolize_keys.slice(*Model.members).reverse_merge(credits_per_1000_characters: nil)) }
  end

  def self.find(kind, key)
    self.for(kind).find { |model| model.key == key }
  end

  # Credits for one creation. Speech is charged per started 1,000 characters.
  def self.credits_for(model, prompt)
    return 0 unless model.credits_per_1000_characters

    (prompt.to_s.length / 1000.0).ceil * model.credits_per_1000_characters
  end

  def self.config
    @config ||= YAML.load_file(Rails.root.join("config/creation_models.yml"))
  end
end
