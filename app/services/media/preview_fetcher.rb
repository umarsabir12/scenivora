require "tmpdir"

module Media
  # Makes a small JPEG preview of a scene candidate: the image itself, or a video's poster frame.
  class PreviewFetcher
    MAX_BYTES = 30.megabytes
    WIDTH = 512

    def initialize(ffmpeg: Ffmpeg.new)
      @ffmpeg = ffmpeg
    end

    # JPEG bytes, or nil when the candidate has nothing to preview.
    def jpeg(media)
      url = media.video? ? media.poster_url : media.image_url
      return if url.blank? && !media.stored_file?

      Dir.mktmpdir("preview-#{media.id}") do |dir|
        source = File.join(dir, "source")
        if media.stored_file?
          File.binwrite(source, media.file.download)
        else
          Download.to_file(url, source, max_bytes: MAX_BYTES)
        end
        File.binread(@ffmpeg.jpeg_preview(source, File.join(dir, "preview.jpg"), width: WIDTH))
      end
    end
  end
end
