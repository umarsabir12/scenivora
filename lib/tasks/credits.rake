namespace :credits do
  desc "Grant credits to a user: bin/rails \"credits:grant[email@example.com,50]\""
  task :grant, %i[email amount] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    amount = Integer(args.fetch(:amount))
    abort "Amount must be positive" unless amount.positive?

    user.grant_credits!(amount, reason: "manual_grant")
    puts "Granted #{amount} credits to #{user.email}. Balance: #{user.credits_balance}"
  end
end
