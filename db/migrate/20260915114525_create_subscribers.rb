# メール購読者のテーブルを作る。オーディエンスごとに1メールアドレス1件。
class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      t.string :email, null: false
      t.references :audience, null: false, foreign_key: true
      t.datetime :confirmed_at
      t.datetime :unsubscribed_at
      t.json :utm, null: false

      t.timestamps
    end

    add_index :subscribers, [ :audience_id, :email ], unique: true
  end
end
