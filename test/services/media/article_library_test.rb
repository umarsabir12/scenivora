require "test_helper"

class Media::ArticleLibraryTest < ActiveSupport::TestCase
  # Returns canned results per article, fails for the ones it's told to.
  class FakeFetcher
    attr_reader :calls

    def initialize(results, failing: [])
      @results = results
      @failing = failing
      @calls = []
    end

    def images(article)
      @calls << article
      raise Media::Error, "en.wikipedia.org responded with 500" if @failing.include?(article)

      @results.fetch(article, [])
    end
  end

  def picture(name, description: nil, categories: nil)
    Media::ImageResult.new(provider: "wikipedia_article", image_url: "https://upload.wikimedia.org/#{name}.jpg",
                           page_url: "https://en.wikipedia.org/wiki/File:#{name}.jpg", credit: "x", license: "Public domain",
                           description: description, categories: categories, source_article: "x")
  end

  setup do
    @toddler = picture("Prince_Philip_as_a_toddler", description: "Prince Philip of Greece aged two")
    @calypso = picture("HMS_Calypso_(D61)", description: "Light cruiser at Malta")
    @wedding = picture("Wedding_1947", categories: "Wedding of Princess Elizabeth and Prince Philip")
    @fetcher = FakeFetcher.new({
      "Prince Philip, Duke of Edinburgh" => [ @toddler, @wedding ],
      "HMS Calypso (D61)" => [ @calypso, @toddler ]
    }, failing: [ "Broken Article" ])
  end

  def library(articles = [ "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)", "Broken Article", "No Such Article" ], limit: 60)
    Media::ArticleLibrary.build(articles, fetcher: @fetcher, limit: limit)
  end

  test "fetches each article once, dedupes pictures across articles, and skips articles that fail" do
    lib = library([ "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)", "HMS Calypso (D61)", "Broken Article", "" ])

    assert_equal [ "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)", "Broken Article" ], @fetcher.calls
    assert_equal [ @toddler, @wedding, @calypso ], lib.items
  end

  test "gives a scene its own articles' pictures first" do
    assert_equal [ @calypso ], library.for_articles([ "HMS Calypso (D61)" ])
  end

  test "puts a scene's own pictures that fit its text first, and lets articles take turns" do
    ships = (1..3).map { |i| picture("Royal_Navy_ship_#{i}") }
    fetcher = FakeFetcher.new({ "Royal Navy" => ships, "HMS Calypso (D61)" => [ @calypso ],
                                "Prince Philip, Duke of Edinburgh" => [ @toddler, @wedding ] })
    lib = Media::ArticleLibrary.build([ "Royal Navy", "HMS Calypso (D61)", "Prince Philip, Duke of Edinburgh" ], fetcher: fetcher)

    assert_equal [ ships[0], @calypso, ships[1], ships[2] ], lib.for_articles([ "Royal Navy", "HMS Calypso (D61)" ])
    assert_equal [ @wedding, @toddler ], lib.for_articles([ "Prince Philip, Duke of Edinburgh" ], "the 1947 wedding")
  end

  test "matches library pictures by words in their title, description or categories" do
    lib = library

    assert_equal [ @calypso ], lib.matching("The cruiser HMS Calypso carried the family from Corfu")
    assert_equal [ @wedding ], lib.matching("Philip married Princess Elizabeth at her wedding in 1947") - [ @toddler ]
    assert_equal [], lib.matching("the and of")
  end

  test "lists the pictures sharing the most words first" do
    assert_equal [ @toddler, @wedding ], library.matching("Philip of Greece as a toddler, before his wedding")
  end

  test "ignores words found in most of the library, such as the subject's name" do
    portraits = (1..8).map { |i| picture("Prince_Philip_#{i}", description: "Prince Philip visiting a town") }
    fetcher = FakeFetcher.new({ "Prince Philip, Duke of Edinburgh" => [ *portraits, @toddler, @wedding ] })
    lib = Media::ArticleLibrary.build([ "Prince Philip, Duke of Edinburgh" ], fetcher: fetcher)

    assert_equal [ @toddler ], lib.matching("Philip as a toddler")
    assert_equal [], lib.matching("Prince Philip later in life")
  end

  test "is capped" do
    assert_equal 2, library(limit: 2).items.size
  end
end
