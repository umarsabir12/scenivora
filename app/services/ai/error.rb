module Ai
  # Raised by any AI provider service. Callers rescue this one class, whichever provider failed.
  class Error < StandardError; end
end
