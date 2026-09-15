# クラスタと投稿の対応表。
class ClusterPost < ApplicationRecord
  belongs_to :cluster
  belongs_to :post

  validates :post_id, uniqueness: { scope: :cluster_id }
end
