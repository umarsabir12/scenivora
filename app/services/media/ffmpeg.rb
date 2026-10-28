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

    # Turns one still image into a 1080p clip of exactly `frames` frames, with a slow zoom in
    # (or out). The image is fitted first: see FILL_RATIO_RANGE.
    def still_clip(image_path, frames, output_path, fps:, zoom_in: true)
      big_w = VIDEO_WIDTH * 2 # zoompan jitters at output size, so work at double size
      big_h = VIDEO_HEIGHT * 2
      zoom = zoom_in ? "1+#{ZOOM}*on/#{frames}" : "1+#{ZOOM}-#{ZOOM}*on/#{frames}"
      motion = "zoompan=z='#{zoom}':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=#{frames}:" \
               "s=#{VIDEO_WIDTH}x#{VIDEO_HEIGHT}:fps=#{fps},format=yuv420p"

      filter =
        if fill?(image_path)
          "[0:v]scale=#{big_w}:#{big_h}:force_original_aspect_ratio=increase,crop=#{big_w}:#{big_h},setsar=1,#{motion}[v]"
        else
          "[0:v]split=2[a][b];" \
          "[a]scale=#{big_w}:#{big_h}:force_original_aspect_ratio=increase,crop=#{big_w}:#{big_h},gblur=sigma=40,eq=brightness=-0.15[bg];" \
          "[b]scale=#{big_w}:#{big_h}:force_original_aspect_ratio=decrease[fg];" \
          "[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,#{motion}[v]"
        end

      ffmpeg!("-i", image_path, "-filter_complex", filter, "-map", "[v]", "-frames:v", frames.to_s,
              "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-an", output_path)
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

    def thumbnail(video_path, output_path)
      ffmpeg!("-ss", "1", "-i", video_path, "-frames:v", "1", "-vf", "scale=1280:720", output_path)
      output_path
    end

    def duration_ms(path)
      seconds = run!(self.class.ffprobe_bin, "-v", "error", "-show_entries", "format=duration",
                     "-of", "default=noprint_wrappers=1:nokey=1", path)
      (Float(seconds.strip) * 1000).round
    end

    # [width, height] of an image or video.
    def dimensions(path)
      output = run!(self.class.ffprobe_bin, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                    "-of", "csv=p=0:s=x", path)
      output.strip.split("x").map { |value| Integer(value) }
    end

    # Captions need the `subtitles` filter, which exists only when ffmpeg was built with libass.
    def supports_captions?
      @supports_captions ||= run!(self.class.ffmpeg_bin, "-hide_banner", "-filters").match?(/^\s*\S+\s+subtitles\s/)
    end

    private
      def fill?(image_path)
        width, height = dimensions(image_path)
        FILL_RATIO_RANGE.cover?(width.to_f / height)
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
