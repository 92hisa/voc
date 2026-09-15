# 週ごと・レンズごとに似た投稿をまとめたかたまり。name と representative_text はAIが付ける。
class Cluster < ApplicationRecord
  belongs_to :audience
  has_many :cluster_posts, dependent: :destroy
  has_many :posts, through: :cluster_posts
  has_many :weekly_snapshots, dependent: :destroy

  validates :lens, presence: true, inclusion: { in: Classification::LENSES }
  validates :week_start, presence: true
  validates :name, presence: true

  scope :for_week, ->(week_start) { where(week_start: week_start) }
  scope :for_lens, ->(lens) { where(lens: lens) }
end
