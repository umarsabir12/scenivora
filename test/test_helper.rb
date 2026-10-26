ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Replaces `klass.new` with `instance` for the duration of the block.
    def with_stubbed_new(klass, instance)
      original = klass.method(:new)
      klass.define_singleton_method(:new) { |*| instance }
      yield
    ensure
      klass.define_singleton_method(:new, original)
    end
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers
  end
end
