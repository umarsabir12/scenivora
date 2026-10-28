require "test_helper"

class Media::DownloadTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:chunks) do
    def read_body(&block)
      chunks.each(&block)
    end
  end

  test "writes the body to the file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "file")
      Media::Download.write_body(FakeResponse.new([ "ab", "cd" ]), path, 10)

      assert_equal "abcd", File.read(path)
    end
  end

  test "stops when the file is larger than the limit" do
    Dir.mktmpdir do |dir|
      error = assert_raises(Media::Error) do
        Media::Download.write_body(FakeResponse.new([ "a" * 6, "b" * 6 ]), File.join(dir, "file"), 10)
      end
      assert_match "larger than", error.message
    end
  end

  test "refuses plain HTTP" do
    assert_raises(Media::Error) { Media::Download.to_file("http://example.com/a.mp3", "/tmp/never", max_bytes: 10) }
  end
end
