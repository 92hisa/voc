# オーディエンスごとの検索語テーブルを作る。媒体（source）別に持ち、同じ検索語は重複登録できない。
class CreateAudienceQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :audience_queries do |t|
      t.references :audience, null: false, foreign_key: true
      t.string :source, null: false
      t.string :query, null: false
      t.boolean :is_active, null: false, default: true
      t.string :generated_by, null: false

      t.timestamps
    end

    add_index :audience_queries, [ :audience_id, :source, :query ], unique: true
  end
end
