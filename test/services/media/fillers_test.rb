require "test_helper"

class Media::FillersTest < ActiveSupport::TestCase
  def clip(mood, era: "any", name: mood)
    Media::Fillers::Clip.new(mood: mood, era: era, title: name, video_url: "https://upload.wikimedia.org/#{name}.webm",
                             poster_url: "https://upload.wikimedia.org/#{name}.jpg", page_url: "https://commons.wikimedia.org/wiki/File:#{name}.webm",
                             credit: "Archive", license: "Public domain", duration_ms: 20_000)
  end

  setup do
    @clips = [ clip("clouds"), clip("sea", era: "old", name: "dover"), clip("sea", name: "arran"), clip("fire"),
               clip("city", era: "modern"), clip("mist") ]
    @fillers = Media::Fillers.new(clips: @clips)
  end

  test "picks the clip whose mood the scene's words call for, as credited video" do
    result = @fillers.pick("The family sailed into exile across a grey sea.")

    assert_equal "https://upload.wikimedia.org/dover.webm", result.video_url
    assert_equal "Archive", result.credit
    assert_equal "Public domain", result.license
    assert_equal 20_000, result.duration_ms
  end

  test "a scene with no telling word gets a calm clip" do
    assert_equal "https://upload.wikimedia.org/clouds.webm", @fillers.pick("It was not what anyone expected.").video_url
  end

  test "a clip already in the video is used again only when no other fits" do
    used = [ "https://upload.wikimedia.org/dover.webm" ]

    assert_equal "https://upload.wikimedia.org/arran.webm", @fillers.pick("The ship sailed on.", used_urls: used).video_url
  end

  test "modern footage stays out of historical videos" do
    assert_equal "https://upload.wikimedia.org/city.webm", @fillers.pick("Fame came to the city.").video_url
    assert_not_equal "https://upload.wikimedia.org/city.webm", @fillers.pick("Fame came to the city.", historical: true).video_url
  end

  test "a video naming a year before 2000 is historical" do
    assert Media::Fillers.historical?("The Great Molasses Flood of 1919")
    assert Media::Fillers.historical?("In 1975 Stallone wrote Rocky"), "a 2023 skyline would pass for 1975 New York"
    assert_not Media::Fillers.historical?("Ronaldo's 2016 Euro win")
    assert_not Media::Fillers.historical?("How bees make honey")
  end

  test "the configured clips load, and their videos are recognised as filler" do
    clips = Media::Fillers.clips

    assert clips.size >= 10
    assert clips.all? { |c| c.license.match?(Media::CommonsSearch::ALLOWED_LICENSE) }
    assert clips.all? { |c| c.video_url.start_with?("https://upload.wikimedia.org/") }
    assert Media::Fillers.filler?(clips.first.video_url)
    assert_not Media::Fillers.filler?("https://upload.wikimedia.org/other.webm")
  end
end
