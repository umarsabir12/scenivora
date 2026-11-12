require "test_helper"

class Media::CandidateScoreTest < ActiveSupport::TestCase
  Scene = Struct.new(:text, :plan, :search_query)

  def scene(text: "On 15 January 1919 the molasses tank on Commercial Street burst.", subject_type: "historical_event",
            queries: [ "Molasses Flood 1919", "Commercial Street Boston" ], articles: [ "Great Molasses Flood" ],
            intent: "The wrecked waterfront after the flood.")
    Scene.new(text, { "subject_type" => subject_type, "search_queries" => queries, "articles" => articles,
                      "visual_intent" => intent }, queries.first)
  end

  def picture(title, **details)
    Media::ImageResult.new(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/#{title.parameterize}.jpg",
                           page_url: "https://commons.wikimedia.org/wiki/File:#{title.tr(" ", "_")}.jpg", credit: "x",
                           license: "CC0", **details)
  end

  test "a picture named for the scene's subject and year scores above an unrelated one" do
    score = Media::CandidateScore.new(scene)

    wreck = picture("Molasses Flood wreckage 1919", taken_on: "1919-01-16")
    wax = picture("Madame Tussauds wax figures")

    assert_operator score.call(wreck), :>=, Media::CandidateScore::MIN_SCORE
    assert_operator score.call(wax), :<, Media::CandidateScore::MIN_SCORE
  end

  test "a picture from the scene's own article gains, the first article most" do
    score = Media::CandidateScore.new(scene(articles: [ "Great Molasses Flood", "North End, Boston" ]))
    plain = picture("Commercial Street 1919")

    first = score.call(plain.with(source_article: "Great Molasses Flood"))
    second = score.call(plain.with(source_article: "North End, Boston"))

    assert_operator first, :>, second
    assert_operator second, :>, score.call(plain)
  end

  test "a photo Commons says depicts the scene's subject reaches the check even with an unhelpful name" do
    stallone = scene(text: "In 1975 Sylvester Stallone was nearly broke.", subject_type: "real_person",
                     queries: [ "Sylvester Stallone 1975" ], articles: [ "Sylvester Stallone" ], intent: "A portrait.")
    score = Media::CandidateScore.new(stallone)
    vague = picture("IMG 4031", source_article: "Sylvester Stallone")

    assert_operator score.call(vague), :<, Media::CandidateScore::MIN_SCORE
    assert_operator score.call(vague.with(provider: "commons_depicts")), :>=, Media::CandidateScore::MIN_SCORE
    late = vague.with(provider: "commons_depicts", taken_on: "2009-09-05")
    assert_operator score.call(late), :<, score.call(vague.with(provider: "commons_depicts", taken_on: "1976-11-21")),
                    "a photo from the scene's own years still beats one from decades later"
  end

  test "a photo taken long after a historical moment loses points, unless the scene speaks of today" do
    modern = picture("Commercial Street Boston", taken_on: "2015-06-01")
    old = picture("Commercial Street Boston", taken_on: "1919-01-16")

    assert_operator Media::CandidateScore.new(scene).call(modern), :<, Media::CandidateScore.new(scene).call(old)
    today = scene(text: "Today Commercial Street is a quiet park where the tank stood in 1919.")
    assert_operator Media::CandidateScore.new(today).call(modern), :>, Media::CandidateScore.new(scene).call(modern)
  end

  test "a later portrait still introduces a person" do
    born = scene(text: "Cristiano Ronaldo was born in Funchal in 1985.", subject_type: "real_person",
                 queries: [ "Cristiano Ronaldo", "Funchal" ], articles: [ "Cristiano Ronaldo" ])

    assert_operator Media::CandidateScore.new(born).call(picture("Cristiano Ronaldo 2012", taken_on: "2012-06-09")), :>=,
                    Media::CandidateScore::MIN_SCORE
  end

  test "maps and logos lose points unless the scene asks for one" do
    score = Media::CandidateScore.new(scene)
    map = picture("Commercial Street Boston map 1919")

    assert_operator score.call(map), :<, score.call(picture("Commercial Street Boston 1919"))
    asks = Media::CandidateScore.new(scene(queries: [ "Commercial Street map", "Molasses Flood 1919" ]))
    assert_operator asks.call(map), :>, score.call(map)
  end

  test "a file the plan names gains" do
    named = scene(intent: "Open on the BostonMolassesDisaster photo from Great Molasses Flood.")

    assert_operator Media::CandidateScore.new(named).call(picture("BostonMolassesDisaster")), :>,
                    Media::CandidateScore.new(scene).call(picture("BostonMolassesDisaster"))
  end

  test "words in most of the video's pictures count for little" do
    plain = Media::CandidateScore.new(scene)
    common = Media::CandidateScore.new(scene, common_words: %w[molas flood])
    title = picture("Molasses Flood")

    assert_operator common.call(title), :<, plain.call(title)
  end

  test "best keeps the top few above the bar, best first, and one of each numbered series" do
    score = Media::CandidateScore.new(scene)
    aerial = (1..3).map { |n| picture("Molasses Flood Commercial Street aerial 0#{n}", taken_on: "1919") }
    wreck = picture("Molasses Flood wreckage Commercial Street 1919", taken_on: "1919-01-16", source_article: "Great Molasses Flood")
    wax = picture("Madame Tussauds wax figures")

    best = score.best([ wax, *aerial, wreck ], limit: 4)

    assert_equal [ wreck, aerial.first ], best
  end
end
