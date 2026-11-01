module Ai
  # The AI provider's account has run out of credit. Every later call fails the same way, so a run
  # stops instead of carrying on with unchecked pictures.
  class OutOfCredits < Error; end
end
