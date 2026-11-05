require "test_helper"

class Media::CommonsMetadataTest < ActiveSupport::TestCase
  def artist(html)
    Media::CommonsMetadata.artist({ "Artist" => { "value" => html } })
  end

  test "the author is the readable text of the Artist field" do
    assert_equal "Photographer Jane", artist("<a href='https://example.org'>Photographer Jane</a>")
  end

  test "an author given only as a numbered link is named after its Flickr account" do
    assert_equal "joshuatreenp on Flickr", artist(%(<a class="external autonumber" href="https://www.flickr.com/photos/joshuatreenp/">[1]</a>))
  end

  test "no usable author is nil, so the caller's default applies" do
    assert_nil artist(%(<a href="https://example.org/">[1]</a>))
    assert_nil Media::CommonsMetadata.artist({})
  end
end
