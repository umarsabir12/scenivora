ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/production_steps"

# dotenv loads a real key from .env. Clear it so no test can reach OpenAI by accident; a
# missing key makes any unstubbed call fail fast instead of costing money.
ENV.delete("OPENAI_API_KEY")

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Replaces a module or class method with `implementation` for the duration of the block.
    def with_stubbed_method(object, name, implementation)
      original = object.method(name)
      object.define_singleton_method(name, &implementation)
      yield
    ensure
      object.define_singleton_method(name, original)
    end

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

module ActiveSupport
  class TestCase
    include ProductionSteps
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers
  end
end
