require "test_helper"

class Media::CommonsVideoSearchTest < ActiveSupport::TestCase
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

  def page(title, mime: "video/webm", license: "Public domain", duration: 120, width: 640, derivatives: nil)
    { "title" => title, "videoinfo" => [ {
      "mime" => mime, "duration" => duration, "width" => width, "height" => 480, "url" => "https://upload.wikimedia.org/original/#{title.parameterize}",
      "thumburl" => "https://upload.wikimedia.org/thumb/#{title.parameterize}.jpg", "descriptionurl" => "https://commons.wikimedia.org/wiki/#{title}",
      "derivatives" => derivatives || [
        { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 240, "src" => "https://upload.wikimedia.org/transcoded/240.webm" },
        { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 480, "src" => "https://upload.wikimedia.org/transcoded/480.webm" },
        { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 1080, "src" => "https://upload.wikimedia.org/transcoded/1080.webm" }
      ],
      "extmetadata" => { "Artist" => { "value" => "<i>Newsreel</i>" }, "LicenseShortName" => { "value" => license } }
    } ] }
  end

  def search_with(*pages)
    http = FakeHttp.new(search: { "pages" => pages.map { |p| { "title" => p["title"] } } }, metadata: { "query" => { "pages" => pages } })
    [ Media::CommonsVideoSearch.new(http: http).search("Partition", limit: 5), http ]
  end

  test "returns reusable videos with poster, credit, license, duration and a transcode up to 720p" do
    results, http = search_with(page("File:Refugees.webm"))

    video = results.sole
    assert_equal "https://upload.wikimedia.org/transcoded/480.webm", video.video_url
    assert_equal "https://upload.wikimedia.org/thumb/file-refugees-webm.jpg", video.poster_url
    assert_equal "Newsreel", video.credit
    assert_equal 120_000, video.duration_ms
    assert_equal "Partition filetype:video", http.calls.first.last[:q]
    assert_equal "videoinfo", http.calls.last.last[:prop]
  end

  test "uses the original file when there is no suitable transcode" do
    results, = search_with(page("File:Old.ogv", mime: "application/ogg", derivatives: []))

    assert_equal "https://upload.wikimedia.org/original/file-old-ogv", results.sole.video_url
  end

  test "skips non-reusable licenses, audio-only files and very short clips" do
    results, = search_with(page("File:NC.webm", license: "CC BY-NC 4.0"),
                           page("File:Song.ogg", mime: "application/ogg", width: 0),
                           page("File:Blip.webm", duration: 1))

    assert_equal [], results
  end

  test "prefers Wikimedia's transcode over the original upload at the same height" do
    original_and_transcode = [
      { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 480, "src" => "https://upload.wikimedia.org/wikipedia/commons/5/57/Original.webm" },
      { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 480, "src" => "https://upload.wikimedia.org/wikipedia/commons/transcoded/5/57/Original.webm.480p.vp9.webm" }
    ]
    results, = search_with(page("File:Original.webm", derivatives: original_and_transcode))

    assert_includes results.sole.video_url, "/transcoded/"
  end

  test "skips videos only available below 360p, and returns the title" do
    low = [ { "type" => "video/webm; codecs=\"vp9, opus\"", "height" => 240, "src" => "https://upload.wikimedia.org/transcoded/240.webm" } ]
    results, = search_with(page("File:Blurry.ogv", derivatives: low), page("File:First flights.webm"))

    assert_equal [ "First flights" ], results.map(&:title)
  end
end
