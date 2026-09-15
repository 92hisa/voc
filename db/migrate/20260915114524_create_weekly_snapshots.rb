# 週次スナップショット（件数・前週比・狙い目スコア）のテーブルを作る。このデータは削除しない資産。
class CreateWeeklySnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_snapshots do |t|
      t.references :audience, null: false, foreign_key: true
      t.date :week_start, null: false
      t.string :lens, null: false
      t.references :cluster, null: false, foreign_key: true
      t.integer :post_count, null: false, default: 0
      t.integer :author_count, null: false, default: 0
      t.float :wow_change
      t.integer :supply_count, null: false, default: 0
      t.float :opportunity_score

      t.timestamps
    end

    add_index :weekly_snapshots, [ :audience_id, :week_start, :lens, :cluster_id ],
              unique: true, name: "index_weekly_snapshots_on_audience_week_lens_cluster"
  end
end
