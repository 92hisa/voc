# 投稿のAI分類結果（レンズ・買う側か売る側か・意図）のテーブルを作る。1投稿につき1件（再実行は上書き）。
class CreateClassifications < ActiveRecord::Migration[8.1]
  def change
    create_table :classifications do |t|
      t.references :post, null: false, foreign_key: true, index: { unique: true }
      t.string :lens, null: false
      t.string :side, null: false
      t.string :intent, null: false
      t.float :confidence
      t.string :model, null: false
      t.datetime :classified_at, null: false

      t.timestamps
    end

    add_index :classifications, [ :lens, :side ]
  end
end
