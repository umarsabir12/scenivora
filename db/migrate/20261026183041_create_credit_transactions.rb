class CreateCreditTransactions < ActiveRecord::Migration[8.0]
  def change
    # One row per change to a user's credit balance: grants (positive) and charges (negative).
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, foreign_key: { on_delete: :nullify }
      t.integer :amount, null: false
      t.integer :balance_after, null: false
      t.string :reason, null: false

      t.timestamps
    end

    add_index :credit_transactions, [ :user_id, :created_at ]
  end
end
