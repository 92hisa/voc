# 収集に使う検索語。媒体（source）ごとに持ち、AI生成か人手かを generated_by に残す。
class AudienceQuery < ApplicationRecord
  SOURCES = %w[youtube bluesky threads].freeze
  GENERATED_BY = %w[ai human].freeze

  belongs_to :audience

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :query, presence: true, uniqueness: { scope: [ :audience_id, :source ] }
  validates :generated_by, presence: true, inclusion: { in: GENERATED_BY }

  scope :active, -> { where(is_active: true) }
  scope :for_source, ->(source) { where(source: source) }
end
