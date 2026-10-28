require "test_helper"

class Media::CommonsAudioSearchTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :calls

    def initialize(search:, metadata:)
      @search = search
      @metadata = metadata
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      url == Media::CommonsSearch::SEARCH_ENDPOINT ? @search : @metadata
    end
  end

  def page(title, mime:, license:, duration:, size: 5_000_000)
    { "title" => title, "imageinfo" => [ {
      "mime" => mime, "size" => size, "duration" => duration,
      "url" => "https://upload.wikimedia.org/#{title.parameterize}", "descriptionurl" => "https://commons.wikimedia.org/wiki/#{title}",
      "extmetadata" => { "Artist" => { "value" => "<b>Ross</b>" }, "LicenseShortName" => { "value" => license } }
    } ] }
  end

  def http
    FakeHttp.new(
      search: { "pages" => [ { "title" => "File:Home Song.wav" }, { "title" => "File:Long.ogg" },
                             { "title" => "File:Short.ogg" }, { "title" => "File:NC.ogg" }, { "title" => "File:Photo.jpg" } ] },
      metadata: { "query" => { "pages" => [
        page("File:Home Song.wav", mime: "audio/wav", license: "CC BY 4.0", duration: 185.5),
        page("File:Long.ogg", mime: "application/ogg", license: "CC0", duration: 7_200),
        page("File:Short.ogg", mime: "application/ogg", license: "CC0", duration: 20),
        page("File:NC.ogg", mime: "application/ogg", license: "CC BY-NC 4.0", duration: 120),
        page("File:Photo.jpg", mime: "image/jpeg", license: "CC0", duration: nil)
      ] } }
    )
  end

  test "keeps reusable tracks of a usable length, with title, credit, license and duration" do
    results = Media::CommonsAudioSearch.new(http: http).search("ambient")

    assert_equal [ "Home Song" ], results.map(&:title)
    track = results.first
    assert_equal "Ross", track.credit
    assert_equal "CC BY 4.0", track.license
    assert_equal 185_500, track.duration_ms
    assert_equal "https://upload.wikimedia.org/file-home-song-wav", track.audio_url
  end

  test "searches with the audio filter" do
    fake = http
    Media::CommonsAudioSearch.new(http: fake).search("ambient")

    assert_equal "ambient filetype:audio", fake.calls.first.last[:q]
  end

  test "skips files over 40 MB" do
    fake = FakeHttp.new(search: { "pages" => [ { "title" => "File:Big.wav" } ] },
      metadata: { "query" => { "pages" => [ page("File:Big.wav", mime: "audio/wav", license: "CC0", duration: 200, size: 50_000_000) ] } })

    assert_equal [], Media::CommonsAudioSearch.new(http: fake).search("x")
  end
end
