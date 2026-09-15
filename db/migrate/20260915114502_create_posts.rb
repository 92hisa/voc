# 収集した投稿（YouTubeコメント・Bluesky投稿）のテーブルを作る。投稿者の氏名やアイコンは保存しない。
class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :audience, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false
      t.text :text, null: false
      t.datetime :posted_at, null: false
      t.json :metrics, null: false
      t.string :video_id
      t.datetime :fetched_at, null: false
      t.datetime :expires_at

      t.timestamps
    end

    # 同じ投稿を二重に取り込まないための一意制約
    add_index :posts, [ :source, :external_id ], unique: true
    add_index :posts, [ :audience_id, :posted_at ]
    add_index :posts, :expires_at
  end
end
