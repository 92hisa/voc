# 週ごと・レンズごとに似た投稿をまとめたクラスタのテーブルを作る。
class CreateClusters < ActiveRecord::Migration[8.1]
  def change
    create_table :clusters do |t|
      t.references :audience, null: false, foreign_key: true
      t.string :lens, null: false
      t.date :week_start, null: false
      t.string :name, null: false
      t.text :representative_text

      t.timestamps
    end

    add_index :clusters, [ :audience_id, :week_start, :lens ]
  end
end
