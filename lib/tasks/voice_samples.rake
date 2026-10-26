namespace :voice_samples do
  desc "Generate any missing voice samples into public/voice_samples. Paid, but only for voices without a file."
  task generate: :environment do
    dir = VoiceSample::STATIC_DIR
    FileUtils.mkdir_p(dir)

    generator = Ai::SpeechGenerator.new
    total_cost = 0

    Ai::SpeechGenerator::VOICES.each_key do |voice|
      path = dir.join("#{voice}.mp3")
      if path.exist?
        puts "skip #{voice} (already exists)"
        next
      end

      result = generator.call(text: VoiceSample::SAMPLE_TEXT, voice: voice)
      File.binwrite(path, result.audio)
      total_cost += result.cost_usd
      puts "wrote #{voice}.mp3"
    end

    puts "estimated cost this run: $#{total_cost.round(5)}"
  end
end
