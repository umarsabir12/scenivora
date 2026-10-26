class ConvertUsersToDevise < ActiveRecord::Migration[8.0]
  def change
    # Devise's column names. Existing password hashes are bcrypt, which Devise also uses.
    rename_column :users, :email_address, :email
    rename_column :users, :password_digest, :encrypted_password

    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime
    add_index :users, :reset_password_token, unique: true

    # Devise tracks the signed-in user in the Rails session cookie, so the sessions table is no longer used.
    drop_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
