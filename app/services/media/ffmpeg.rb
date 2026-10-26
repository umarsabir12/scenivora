require "open3"

module Media
  # Thin wrapper over the ffmpeg and ffprobe binaries. Requires them on PATH.
  class Ffmpeg
    class Error < StandardError; end

    INSTALL_HINT = "ffmpeg is not installed. Install it with `brew install ffmpeg`, then restart the worker."

    # Joins MP3 parts into one file without re-encoding.
    def concat(part_paths, output_path)
      list_path = File.join(File.dirname(output_path), "parts.txt")
      File.write(list_path, part_paths.map { |path| "file '#{path}'" }.join("\n"))

      run!("ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
           "-i", list_path, "-c", "copy", output_path)
      output_path
    end

    def duration_ms(path)
      seconds = run!("ffprobe", "-v", "error", "-show_entries", "format=duration",
                     "-of", "default=noprint_wrappers=1:nokey=1", path)
      (Float(seconds.strip) * 1000).round
    end

    private
      def run!(*command)
        stdout, stderr, status = Open3.capture3(*command)
        raise Error, "#{command.first} failed: #{stderr.strip.lines.last.to_s.strip}" unless status.success?

        stdout
      rescue Errno::ENOENT
        raise Error, INSTALL_HINT
      end
  end
end
