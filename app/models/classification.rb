# 投稿のAI分類結果。1投稿につき1件で、分類し直したときは上書きする。
class Classification < ApplicationRecord
  LENSES = %w[pain seeking money switching trending noise].freeze
  SIDES = %w[buyer seller peer unknown].freeze
  INTENTS = %w[now vague none].freeze

  belongs_to :post

  validates :post_id, uniqueness: true
  validates :lens, presence: true, inclusion: { in: LENSES }
  validates :side, presence: true, inclusion: { in: SIDES }
  validates :intent, presence: true, inclusion: { in: INTENTS }
  validates :model, presence: true
  validates :classified_at, presence: true

  # 集計は買う側（buyer）の投稿だけを使う
  scope :buyer, -> { where(side: "buyer") }
  scope :for_lens, ->(lens) { where(lens: lens) }
end
