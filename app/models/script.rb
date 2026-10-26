class Script < ApplicationRecord
  belongs_to :project

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :project_id }
  validates :body, presence: true

  # Fingerprint of the narration text, used to detect edits after voice generation.
  def digest
    Digest::SHA256.hexdigest(body)
  end

  def word_count
    body.split.size
  end
end
