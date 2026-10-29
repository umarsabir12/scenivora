require "test_helper"

class Media::QueryVariantsTest < ActiveSupport::TestCase
  test "never drops the subject: Prince Philip Corfu 1922 never becomes Prince or Corfu" do
    variants = Media::QueryVariants.for([ "Prince Philip Corfu 1922" ], limit: 10,
                                        topic: "Prince Philip: the baby smuggled out of Greece in an orange box")

    assert_equal [ "Prince Philip Corfu 1922", "Prince Philip 1922", "Prince Philip Corfu" ], variants

    # Without a topic the whole leading name is kept, which is still never a single word.
    without_topic = Media::QueryVariants.for([ "Prince Philip Corfu 1922" ], limit: 10)
    assert_equal [ "Prince Philip Corfu 1922", "Prince Philip Corfu" ], without_topic
    (variants + without_topic).each { |query| assert_not_includes %w[Prince Corfu Philip], query }
  end

  test "keeps the planner's queries first, years in the broader forms, and one form without the year last" do
    variants = Media::QueryVariants.for([ "Karachi harbour 1876", "Indian National Congress meeting 1900s" ], limit: 10)

    assert_equal [ "Karachi harbour 1876", "Indian National Congress meeting 1900s", "Karachi 1876",
                   "Karachi Indian National Congress 1900s", "Karachi harbour" ], variants
  end

  test "every form has at least 2 words, and duplicates and the limit are respected" do
    variants = Media::QueryVariants.for([ "Jinnah travels to England", "jinnah travels to england", nil, "", "Karachi" ], limit: 4)

    assert_equal [ "Jinnah travels to England", "Jinnah England", "Jinnah travels", "Jinnah Karachi" ], variants
  end

  test "drops whole names, never half of one" do
    variants = Media::QueryVariants.for([ "William Gorgas Panama Canal", "Gorgas sanitation measures" ], limit: 10,
                                        topic: "The construction of the Panama Canal")

    assert_equal [ "William Gorgas Panama Canal", "Gorgas sanitation measures", "Panama Canal",
                   "Panama Canal Gorgas", "Panama Canal Gorgas sanitation" ], variants
  end

  test "uses the topic's main name when the first query names nobody" do
    variants = Media::QueryVariants.for([ "steam shovel excavation 1910" ], limit: 10,
                                        topic: "The Panama Canal: how workers cut through a continent")

    assert_equal "Panama Canal", Media::QueryVariants.subject_of("The Panama Canal: how workers cut through a continent")
    assert variants.drop(1).all? { |query| query.include?("Panama Canal") }, variants.inspect
    assert_includes variants, "Panama Canal steam 1910"
  end

  test "reads names joined by small words as one subject" do
    assert_equal "Khalid ibn al-Walid", Media::QueryVariants.subject_of("Khalid ibn al-Walid, the Sword of Allah")
    assert_equal "Battle of Yarmouk", Media::QueryVariants.subject_of("Battle of Yarmouk 636")
  end

  test "an all-lowercase query without a topic keeps its 2-word forms only" do
    assert_equal [ "crossroads symbolism" ], Media::QueryVariants.for([ "crossroads symbolism" ], limit: 5)
  end
end
