class SceneImage < ApplicationRecord
  UPLOAD_PROVIDER = "upload".freeze
  AI_PROVIDER = "ai".freeze
  UPLOAD_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_UPLOAD_BYTES = 10.megabytes
  MEDIA_TYPES = %w[image video].freeze

  belongs_to :scene
  has_one_attached :file

  validates :provider, presence: true
  validates :media_type, inclusion: { in: MEDIA_TYPES }
  validates :image_url, presence: true, unless: :stored_file?
  validate :file_attached, if: :stored_file?
  validate :acceptable_upload, if: :upload?

  # A readable title for a sourced candidate, from its Wikimedia page or file name.
  def source_title
    name = page_url.to_s[/File:(.+)\z/, 1] || image_url.to_s.split("?").first.to_s.split("/").last.to_s
    URI.decode_www_form_component(name.to_s).sub(/\.[a-z0-9]+\z/i, "").tr("_", " ")
  rescue ArgumentError
    name.to_s
  end

  def video?
    media_type == "video"
  end

  # Where a scene's clip starts in a source video: a quarter of the way in (archive films often
  # open with title cards), but early enough that the whole scene fits when the video is long enough.
  def self.default_clip_start(video_ms, scene_ms)
    [ [ video_ms / 4, video_ms - scene_ms ].min, 0 ].max
  end

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
