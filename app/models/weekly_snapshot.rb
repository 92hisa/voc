# 週次スナップショット（クラスタごとの件数・前週比・狙い目スコア）。このデータは削除しない。
class WeeklySnapshot < ApplicationRecord
  belongs_to :audience
  belongs_to :cluster

  validates :lens, presence: true, inclusion: { in: Classification::LENSES }
  validates :week_start, presence: true
  validates :cluster_id, uniqueness: { scope: [ :audience_id, :week_start, :lens ] }
  validates :post_count, :author_count, :supply_count, numericality: { greater_than_or_equal_to: 0 }

  scope :for_week, ->(week_start) { where(week_start: week_start) }
  scope :for_lens, ->(lens) { where(lens: lens) }
  scope :by_post_count, -> { order(post_count: :desc) }
end
