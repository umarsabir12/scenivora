# Idempotent: safe to run repeatedly with `bin/rails db:seed`.
#
# Development only: creates a sign-in you can use right away.
#   email:    test@example.com
#   password: password123
# Never seed credentials like this in production.
if Rails.env.development?
  user = User.find_or_initialize_by(email: "test@example.com")
  user.password = "password123"
  user.password_confirmation = "password123"
  user.save!
  puts "Development user ready: #{user.email} / password123"
end
