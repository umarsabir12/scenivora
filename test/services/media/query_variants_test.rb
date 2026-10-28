require "test_helper"

class Media::QueryVariantsTest < ActiveSupport::TestCase
  test "keeps the planner's queries first, then broader forms without years and trailing words" do
    variants = Media::QueryVariants.for([ "Karachi 1876", "Indian National Congress meeting 1900s" ], limit: 10)

    assert_equal [ "Karachi 1876", "Indian National Congress meeting 1900s", "Karachi", "Indian National Congress",
                   "Indian National Congress meeting", "Indian National", "Indian" ], variants
  end

  test "tries the names in a query first, then drops filler words and duplicates, and stops at the limit" do
    variants = Media::QueryVariants.for([ "Jinnah travels to England", "jinnah travels to england", nil, "" ], limit: 4)

    assert_equal [ "Jinnah travels to England", "Jinnah England", "Jinnah travels England", "Jinnah travels" ], variants
  end

  test "an all-lowercase query has no names form" do
    assert_equal [ "crossroads symbolism", "crossroads" ], Media::QueryVariants.for([ "crossroads symbolism" ], limit: 5)
  end
end
