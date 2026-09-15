# クラスタと投稿の対応表を作る。同じ組み合わせは1件だけ。
class CreateClusterPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :cluster_posts do |t|
      t.references :cluster, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true

      t.timestamps
    end

    add_index :cluster_posts, [ :cluster_id, :post_id ], unique: true
  end
end
