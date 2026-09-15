# オーディエンス（誰の声を集めるか）。slug は URL と rake タスクの引数に使う。
class Audience < ApplicationRecord
  has_many :audience_queries, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :clusters, dependent: :destroy
  has_many :weekly_snapshots, dependent: :destroy
  has_many :subscribers, dependent: :destroy

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/, message: "は英小文字・数字・ハイフンのみ" }
  validates :name, presence: true

  def to_param
    slug
  end
end
