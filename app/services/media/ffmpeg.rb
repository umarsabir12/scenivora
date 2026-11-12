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
    # A scene longer than MAX_SHOT_SECONDS is cut into shots of MIN_SHOT_SECONDS to MAX_SHOT_SECONDS:
    # a picture holding for 10 seconds feels slow. A still cuts between a wide view, a close-up and a
    # pan; footage cuts to a later part of the clip.
    MIN_SHOT_SECONDS = 3
    MAX_SHOT_SECONDS = 5
    CLOSE_UP = 1.35 # the close-up's magnification over the wide view
    PAN = 1.18      # the pan's
    # A framing is used only when it enlarges the picture's own pixels at most this much; tighter is soft.
    MAX_UPSCALE = 1.75
    # Footage cuts forward between shots by at least MIN_JUMP_MS (shorter reads as a glitch) and at most MAX_JUMP_MS.
    MIN_JUMP_MS = 2_000
    MAX_JUMP_MS = 8_000
    # Streaming from Wikimedia occasionally drops ("Connection reset by peer"); try again this often.
    REMOTE_ATTEMPTS = 3
    REMOTE_TIMEOUT_SECONDS = 30
    # Images whose width/height ratio falls in this range fill the frame (cropping a little).
    # Anything narrower or wider is shown whole over a blurred copy of itself.
    FILL_RATIO_RANGE = (1.45..2.2)
    # The narration's own polish before any mixing: 48 kHz, no rumble under 70 Hz, a gentle
    # compressor, then a limiter for the few sharp peaks. tts-1 voices arrive near -25 LUFS with
    # peaks 24 dB over the average; letting loudnorm alone lift them about 10 dB squashed the voice.
    VOICE_CHAIN = "aresample=48000,highpass=f=70," \
                  "acompressor=threshold=-24dB:ratio=2.5:attack=15:release=200:makeup=6dB," \
                  "alimiter=limit=0.84:attack=5:release=60:level=false".freeze
    # -16 LUFS, not -14: YouTube turns louder audio down anyway, so the extra limiting bought nothing.
    LOUDNESS = "loudnorm=I=-16:TP=-1.5:LRA=11".freeze

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
      list_path = File.join(File.dirname(output_path), "#{File.basename(output_path, ".*")}-parts.txt")
      File.write(list_path, part_paths.map { |path| "file '#{path}'" }.join("\n"))

      ffmpeg!("-f", "concat", "-safe", "0", "-i", list_path, "-c", "copy", output_path)
      output_path
    end

    # Splits a scene's frames into shots of MIN_SHOT_SECONDS to MAX_SHOT_SECONDS, as evenly as possible.
    # A scene too short for two shots stays one.
    def self.shot_frames(frames, fps)
      count = [ [ (frames / (fps * MAX_SHOT_SECONDS.to_f)).ceil, frames / (fps * MIN_SHOT_SECONDS) ].min, 1 ].max
      Array.new(count) { |index| (frames * (index + 1) / count) - (frames * index / count) }
    end

    # Turns one still image into a 1080p clip of exactly `frames` frames: a slow zoom in (or out), and
    # for a long scene, cuts to a close-up and a pan of the same picture when it is sharp enough.
    #
    # The motion samples the image at fractional pixel positions every frame (ffmpeg's perspective
    # filter with cubic interpolation), so it glides instead of stepping. Measured on the same photo:
    # 0.043 unevenness against 0.121 for zoompan at 4x and 0.478 for zoompan at 2x.
    def still_clip(image_path, frames, output_path, fps:, zoom_in: true)
      base_path = File.join(File.dirname(output_path), "#{File.basename(output_path, ".*")}-base.png")
      upscale, fill = prepare_still(image_path, base_path)

      framings = still_framings(upscale, fill, zoom_in)
      lengths = framings.size > 1 ? self.class.shot_frames(frames, fps) : [ frames ]
      shots = lengths.each_with_index.map do |shot_frames, index|
        shot_path = lengths.one? ? output_path : output_path.sub(/(\.\w+)\z/, format("-shot%d\\1", index + 1))
        ffmpeg!("-loop", "1", "-framerate", fps.to_s, "-i", base_path, "-vf", motion(framings[index % framings.size], shot_frames),
                "-frames:v", shot_frames.to_s, "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-an", shot_path)
        shot_path
      end
      shots.one? ? output_path : concat(shots, output_path)
    end

    # The still a clip zooms over, made once: fitted to a frame slightly larger than the video,
    # lightly sharpened. Images close to 16:9 fill it; others are shown whole over a blurred copy.
    # Returns how much the wide view enlarges the image's own pixels, and whether the image fills the frame.
    def prepare_still(image_path, base_path)
      width = even(VIDEO_WIDTH * BASE_MARGIN)
      height = even(VIDEO_HEIGHT * BASE_MARGIN)
      image_width, image_height = dimensions(image_path)
      fill = fill_ratio?(image_width, image_height)
      fitted =
        if fill
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
      scales = [ width.to_f / image_width, height.to_f / image_height ]
      [ (fill ? scales.max : scales.min) * VIDEO_WIDTH / width, fill ]
    end

    # Cuts `frames` frames from a video (a local path; an HTTPS URL works but streams slowly, so the
    # render job downloads sources first), starting at start_ms. Video always fills the frame and loses VIDEO_EDGE_TRIM on
    # every edge: on 4:3 archive footage this removes the top and bottom bands where timecodes and
    # channel banners sit, and most corner logos. If the source runs out first, its last frame is held.
    # The clip is silent: the narration is added in the final pass.
    # A long scene cuts forward through the footage between shots, when the source runs long enough.
    def video_clip(source, start_ms, frames, output_path, fps:)
      lengths = self.class.shot_frames(frames, fps)
      jump_ms = lengths.one? ? 0 : footage_jump_ms(source, start_ms, frames, fps, lengths.size)
      return video_shot(source, start_ms, frames, output_path, fps: fps) if jump_ms.zero?

      shot_start_ms = start_ms
      shots = lengths.each_with_index.map do |shot_frames, index|
        shot_path = video_shot(source, shot_start_ms, shot_frames, output_path.sub(/(\.\w+)\z/, format("-shot%d\\1", index + 1)), fps: fps)
        shot_start_ms += shot_frames * 1000 / fps + jump_ms
        shot_path
      end
      concat(shots, output_path)
    end

    # The final pass: draws captions (an ASS file) over a dark band, adds a light vignette, and
    # mixes the narration with optional music, which loops, ducks under the voice and fades out.
    # The voice gets VOICE_CHAIN, the mix is normalised to -16 LUFS, and the output is exactly as
    # long as the narration.
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
      audio =
        if music_path
          inputs += [ "-stream_loop", "-1", "-i", music_path ]
          fade_start = format("%.3f", [ seconds - FADE_OUT_SECONDS, 0 ].max)
          "[2:a]volume=#{format("%.2f", music_volume)},afade=t=in:d=1.5,afade=t=out:st=#{fade_start}:d=#{FADE_OUT_SECONDS}[bed];" \
          "[1:a]#{VOICE_CHAIN},asplit=2[voice][key];" \
          "[bed][key]sidechaincompress=threshold=0.03:ratio=6:attack=40:release=450[ducked];" \
          "[voice][ducked]amix=inputs=2:duration=first:normalize=0,#{LOUDNESS}[a]"
        else
          "[1:a]#{VOICE_CHAIN},#{LOUDNESS}[a]"
        end

      ffmpeg!(*inputs, "-filter_complex", "[0:v]#{video.join(",")}[v];#{audio}", "-map", "[v]", "-map", "[a]",
              "-t", format("%.3f", seconds), "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
              "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", output_path, chdir: work_dir)
      output_path
    end

    # A voice-only file made ready to download: VOICE_CHAIN, -16 LUFS, 48 kHz MP3.
    def master_voice(input_path, output_path)
      ffmpeg!("-i", input_path, "-af", "#{VOICE_CHAIN},#{LOUDNESS}", "-ar", "48000",
              "-c:a", "libmp3lame", "-b:a", "192k", output_path)
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
      # Framings are the visible part of the still at a shot's first and last frame: centre x, centre y
      # and size, as fractions of the still. Shots take them in turn, wide first. The close-up and the
      # pan are used only when the picture has the pixels for them, and the pan only when the picture
      # fills the frame: over a blurred copy, it would mostly move the blur.
      def still_framings(upscale, fill, zoom_in)
        wide = [ [ 0.5, 0.5, 1.0 ], [ 0.5, 0.5, 1 / (1 + ZOOM) ] ]
        close = [ [ 0.5, 0.45, 1 / CLOSE_UP ], [ 0.5, 0.45, 1 / (CLOSE_UP * (1 + ZOOM / 2)) ] ]
        edge = (1 - 1 / PAN) / 2
        pan = [ [ 0.5 - edge, 0.5, 1 / PAN ], [ 0.5 + edge, 0.5, 1 / PAN ] ]
        framings = [ zoom_in ? wide : wide.reverse ]
        framings << close if upscale * CLOSE_UP <= MAX_UPSCALE
        framings << (zoom_in ? pan : pan.reverse) if fill && upscale * PAN <= MAX_UPSCALE
        framings
      end

      # Glides the visible part of the still from the framing's first to its last rectangle.
      def motion(framing, frames)
        (from_x, from_y, from_size), (to_x, to_y, to_size) = framing
        along = ->(from, to) { "(#{from}+(#{to - from})*on/#{frames})" }
        size = along.call(from_size, to_size)
        left = "W*(#{along.call(from_x, to_x)}-#{size}/2)"
        right = "W*(#{along.call(from_x, to_x)}+#{size}/2)"
        top = "H*(#{along.call(from_y, to_y)}-#{size}/2)"
        bottom = "H*(#{along.call(from_y, to_y)}+#{size}/2)"
        corners = { x0: left, y0: top, x1: right, y1: top, x2: left, y2: bottom, x3: right, y3: bottom }
        "perspective=#{corners.map { |key, value| "#{key}='#{value}'" }.join(":")}:interpolation=cubic:eval=frame," \
          "scale=#{VIDEO_WIDTH}:#{VIDEO_HEIGHT}:flags=lanczos,format=yuv420p"
      end

      # How far footage skips between shots: the time left after the scene, spread over the cuts and
      # capped, or 0 (play straight through) when that would be too short to read as a cut.
      def footage_jump_ms(source, start_ms, frames, fps, shots)
        spare_ms = duration_ms(source) - start_ms - frames * 1000 / fps
        jump_ms = [ spare_ms / (shots - 1), MAX_JUMP_MS ].min
        jump_ms >= MIN_JUMP_MS ? jump_ms : 0
      end

      def video_shot(source, start_ms, frames, output_path, fps:)
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
