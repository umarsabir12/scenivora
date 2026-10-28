require "open3"
require "fileutils"

module Media
  # Thin wrapper over the ffmpeg and ffprobe binaries.
  #
  # Uses FFMPEG_BIN / FFPROBE_BIN when set, otherwise Homebrew's ffmpeg-full when it is installed
  # (it includes libass, needed for captions), otherwise whatever `ffmpeg` is on PATH.
  class Ffmpeg
    class Error < StandardError; end

    INSTALL_HINT = "ffmpeg is not installed. Install it with `brew install ffmpeg-full`, then restart the worker."
    FULL_BUILD_DIR = "/opt/homebrew/opt/ffmpeg-full/bin".freeze
    FONTS_DIR = Rails.root.join("fonts").to_s.freeze

    VIDEO_WIDTH = 1920
    VIDEO_HEIGHT = 1080
    FADE_OUT_SECONDS = 3
    ZOOM = 0.07 # how far each scene zooms, as a fraction of the frame
    # The still is prepared this much larger than the frame, so the zoom always has room.
    BASE_MARGIN = 1 + ZOOM + 0.02
    # Landscape crops are taken from this far down the image, where faces usually are.
    CROP_FROM_TOP = 0.35
    # Video is trimmed by this fraction on every edge, which cuts most corner logos and timecodes.
    VIDEO_EDGE_TRIM = 0.05
    # Streaming from Wikimedia occasionally drops ("Connection reset by peer"); try again this often.
    REMOTE_ATTEMPTS = 3
    REMOTE_TIMEOUT_SECONDS = 30
    # Images whose width/height ratio falls in this range fill the frame (cropping a little).
    # Anything narrower or wider is shown whole over a blurred copy of itself.
    FILL_RATIO_RANGE = (1.45..2.2)

    def self.ffmpeg_bin
      ENV["FFMPEG_BIN"].presence || full_build("ffmpeg") || "ffmpeg"
    end

    def self.ffprobe_bin
      ENV["FFPROBE_BIN"].presence || full_build("ffprobe") || "ffprobe"
    end

    def self.full_build(name)
      path = File.join(FULL_BUILD_DIR, name)
      path if File.executable?(path)
    end

    # Joins MP3 parts (or identically encoded MP4 clips) into one file without re-encoding.
    def concat(part_paths, output_path)
      list_path = File.join(File.dirname(output_path), "parts.txt")
      File.write(list_path, part_paths.map { |path| "file '#{path}'" }.join("\n"))

      ffmpeg!("-f", "concat", "-safe", "0", "-i", list_path, "-c", "copy", output_path)
      output_path
    end

    # Turns one still image into a 1080p clip of exactly `frames` frames, with a slow zoom in (or out).
    #
    # The zoom samples the image at fractional pixel positions every frame (ffmpeg's perspective
    # filter with cubic interpolation), so it glides instead of stepping. Measured on the same photo:
    # 0.043 unevenness against 0.121 for zoompan at 4x and 0.478 for zoompan at 2x.
    def still_clip(image_path, frames, output_path, fps:, zoom_in: true)
      base_path = File.join(File.dirname(output_path), "#{File.basename(output_path, ".*")}-base.png")
      prepare_still(image_path, base_path)

      inset = zoom_in ? "(1-1/(1+#{ZOOM}*on/#{frames}))/2" : "(1-1/(1+#{ZOOM}-#{ZOOM}*on/#{frames}))/2"
      corners = { x0: "W*#{inset}", y0: "H*#{inset}", x1: "W-W*#{inset}", y1: "H*#{inset}",
                  x2: "W*#{inset}", y2: "H-H*#{inset}", x3: "W-W*#{inset}", y3: "H-H*#{inset}" }
      motion = "perspective=#{corners.map { |key, value| "#{key}='#{value}'" }.join(":")}:interpolation=cubic:eval=frame," \
               "scale=#{VIDEO_WIDTH}:#{VIDEO_HEIGHT}:flags=lanczos,format=yuv420p"

      ffmpeg!("-loop", "1", "-framerate", fps.to_s, "-i", base_path, "-vf", motion, "-frames:v", frames.to_s,
              "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-an", output_path)
      output_path
    end

    # The still a clip zooms over, made once: fitted to a frame slightly larger than the video,
    # lightly sharpened. Images close to 16:9 fill it; others are shown whole over a blurred copy.
    def prepare_still(image_path, base_path)
      width = even(VIDEO_WIDTH * BASE_MARGIN)
      height = even(VIDEO_HEIGHT * BASE_MARGIN)
      fitted =
        if fill?(image_path)
          "[0:v]scale=#{width}:#{height}:force_original_aspect_ratio=increase:flags=lanczos," \
          "crop=#{width}:#{height}:(iw-ow)/2:(ih-oh)*#{CROP_FROM_TOP}"
        else
          "[0:v]split=2[a][b];" \
          "[a]scale=#{width}:#{height}:force_original_aspect_ratio=increase,crop=#{width}:#{height}," \
          "gblur=sigma=20,eq=brightness=-0.15[bg];" \
          "[b]scale=#{width}:#{height}:force_original_aspect_ratio=decrease:flags=lanczos[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2"
        end

      ffmpeg!("-i", image_path, "-filter_complex", "#{fitted},setsar=1,unsharp=5:5:0.5,eq=contrast=1.05[v]",
              "-map", "[v]", "-frames:v", "1", base_path)
      base_path
    end

    # Cuts `frames` frames from a video (a local path; an HTTPS URL works but streams slowly, so the
    # render job downloads sources first), starting at start_ms. Video always fills the frame and loses VIDEO_EDGE_TRIM on
    # every edge: on 4:3 archive footage this removes the top and bottom bands where timecodes and
    # channel banners sit, and most corner logos. If the source runs out first, its last frame is held.
    # The clip is silent: the narration is added in the final pass.
    def video_clip(source, start_ms, frames, output_path, fps:)
      keep = 1 - 2 * VIDEO_EDGE_TRIM
      seconds = format("%.3f", frames.to_f / fps)
      filter = "fps=#{fps},crop=iw*#{keep}:ih*#{keep}," \
               "scale=#{VIDEO_WIDTH}:#{VIDEO_HEIGHT}:force_original_aspect_ratio=increase:flags=lanczos," \
               "crop=#{VIDEO_WIDTH}:#{VIDEO_HEIGHT},setsar=1,eq=contrast=1.05:saturation=0.92," \
               "tpad=stop_mode=clone:stop_duration=#{seconds},format=yuv420p"

      with_remote_retries(source) do
        ffmpeg!(*remote_options(source), "-ss", format("%.3f", start_ms / 1000.0), "-i", source,
                "-vf", filter, "-frames:v", frames.to_s, "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-an",
                output_path)
      end
      output_path
    end

    # The final pass: draws captions (an ASS file) over a dark band, adds a light vignette, and
    # mixes the narration with optional music, which loops, ducks under the voice and fades out.
    # The mix is normalised to -14 LUFS for YouTube, and the output is exactly as long as the
    # narration.
    def finish(video_path:, narration_path:, output_path:, duration_ms:, music_path: nil, music_volume: 0.0, captions_path: nil)
      seconds = duration_ms / 1000.0
      work_dir = File.dirname(output_path)
      video = [ "vignette=PI/6" ]
      if captions_path
        # Relative paths, run from work_dir, so the filter needs no escaping.
        FileUtils.cp_r(FONTS_DIR, File.join(work_dir, "fonts")) unless Dir.exist?(File.join(work_dir, "fonts"))
        video.unshift("drawbox=y=ih*0.72:w=iw:h=ih*0.28:color=black@0.35:t=fill")
        video << "subtitles=#{File.basename(captions_path)}:fontsdir=fonts"
      end

      inputs = [ "-i", video_path, "-i", narration_path ]
      loudness = "loudnorm=I=-14:TP=-1.5:LRA=11"
      audio =
        if music_path
          inputs += [ "-stream_loop", "-1", "-i", music_path ]
          fade_start = format("%.3f", [ seconds - FADE_OUT_SECONDS, 0 ].max)
          "[2:a]volume=#{format("%.2f", music_volume)},afade=t=in:d=1.5,afade=t=out:st=#{fade_start}:d=#{FADE_OUT_SECONDS}[bed];" \
          "[1:a]asplit=2[voice][key];" \
          "[bed][key]sidechaincompress=threshold=0.03:ratio=6:attack=40:release=450[ducked];" \
          "[voice][ducked]amix=inputs=2:duration=first:normalize=0,#{loudness}[a]"
        else
          "[1:a]#{loudness}[a]"
        end

      ffmpeg!(*inputs, "-filter_complex", "[0:v]#{video.join(",")}[v];#{audio}", "-map", "[v]", "-map", "[a]",
              "-t", format("%.3f", seconds), "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
              "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", output_path, chdir: work_dir)
      output_path
    end

    # A small JPEG of an image (or a video's first frame), for showing to the picture check.
    def jpeg_preview(input_path, output_path, width: 512)
      ffmpeg!("-i", input_path, "-frames:v", "1", "-vf", "scale=#{width}:-2", "-q:v", "4", output_path)
      output_path
    end

    def thumbnail(video_path, output_path)
      ffmpeg!("-ss", "1", "-i", video_path, "-frames:v", "1", "-vf", "scale=1280:720", output_path)
      output_path
    end

    def duration_ms(path)
      seconds = run!(self.class.ffprobe_bin, "-v", "error", "-show_entries", "format=duration",
                     "-of", "default=noprint_wrappers=1:nokey=1", path)
      (Float(seconds.strip) * 1000).round
    end

    # [width, height] of an image or video (a local path or an HTTPS URL).
    def dimensions(path)
      output = run!(self.class.ffprobe_bin, *remote_options(path), "-v", "error", "-select_streams", "v:0",
                    "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", path)
      output.strip.split("x").map { |value| Integer(value) }
    end

    # Captions need the `subtitles` filter, which exists only when ffmpeg was built with libass.
    def supports_captions?
      @supports_captions ||= run!(self.class.ffmpeg_bin, "-hide_banner", "-filters").match?(/^\s*\S+\s+subtitles\s/)
    end

    private
      def fill?(image_path)
        fill_ratio?(*dimensions(image_path))
      end

      def fill_ratio?(width, height)
        FILL_RATIO_RANGE.cover?(width.to_f / height)
      end

      def even(value)
        (value / 2.0).round * 2
      end

      def with_remote_retries(source)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue Error
          raise unless source.to_s.start_with?("https://") && attempts < REMOTE_ATTEMPTS

          sleep(2 * attempts)
          retry
        end
      end

      # Wikimedia asks every client, ffmpeg included, to send a descriptive User-Agent.
      def remote_options(source)
        return [] unless source.to_s.start_with?("https://")

        # rw_timeout (microseconds): give up on a stalled stream instead of waiting forever.
        [ "-user_agent", HttpJson::USER_AGENT, "-rw_timeout", (REMOTE_TIMEOUT_SECONDS * 1_000_000).to_s ]
      end

      def ffmpeg!(*args, chdir: nil)
        run!(self.class.ffmpeg_bin, "-y", "-loglevel", "error", *args, chdir: chdir)
      end

      def run!(*command, chdir: nil)
        options = chdir ? { chdir: chdir } : {}
        stdout, stderr, status = Open3.capture3(*command, **options)
        raise Error, "#{File.basename(command.first)} failed: #{stderr.strip.lines.last.to_s.strip}" unless status.success?

        stdout
      rescue Errno::ENOENT
        raise Error, INSTALL_HINT
      end
  end
end
