# Credit prices for paid actions.
#
# PLACEHOLDERS: pricing has not been decided yet. Change the defaults here, or override them in
# .env, once the credit price is set (see docs/TODO.md).
module CreditPricing
  def self.ai_image
    Integer(ENV.fetch("CREDITS_PER_AI_IMAGE", "5"))
  end
end
