class SceneImage < ApplicationRecord
  UPLOAD_PROVIDER = "upload".freeze
  AI_PROVIDER = "ai".freeze
  UPLOAD_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_UPLOAD_BYTES = 10.megabytes

  belongs_to :scene
  has_one_attached :file

  validates :provider, presence: true
  validates :image_url, presence: true, unless: :stored_file?
  validate :file_attached, if: :stored_file?
  validate :acceptable_upload, if: :upload?

  def upload?
    provider == UPLOAD_PROVIDER
  end

  def ai?
    provider == AI_PROVIDER
  end

  # Uploads and AI images are kept in Active Storage; search results are links to their source.
  def stored_file?
    upload? || ai?
  end

  # Picks this image for its scene and unpicks the others.
  def select!
    transaction do
      scene.images.where.not(id: id).update_all(selected: false)
      update!(selected: true)
    end
  end

  private
    def file_attached
      errors.add(:file, "must be attached") unless file.attached?
    end

    def acceptable_upload
      return unless file.attached?

      errors.add(:file, "must be a JPEG, PNG or WebP image") unless UPLOAD_TYPES.include?(file.content_type)
      errors.add(:file, "must be smaller than 10 MB") if file.byte_size > MAX_UPLOAD_BYTES
    end
end
