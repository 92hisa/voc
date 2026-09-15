# 収集した投稿1件。保存するのは投稿ID・本文・日時・媒体・公開指標だけ（投稿者の氏名やアイコンは保存しない）。
class Post < ApplicationRecord
  SOURCES = %w[youtube bluesky threads].freeze

  # metrics（いいね数など公開指標）は常にハッシュとして扱う
  attribute :metrics, default: -> { {} }

  belongs_to :audience
  has_one :classification, dependent: :destroy
  has_many :cluster_posts, dependent: :destroy
  has_many :clusters, through: :cluster_posts

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :text, presence: true
  validates :posted_at, presence: true
  validates :fetched_at, presence: true

  scope :for_source, ->(source) { where(source: source) }
  scope :posted_between, ->(from, to) { where(posted_at: from...to) }
  scope :unclassified, -> { where.missing(:classification) }
  # 保持期限を過ぎた生投稿（本文はここで消し、集計値は weekly_snapshots に残す）
  scope :expired, ->(now = Time.current) { where(expires_at: ...now) }
end
