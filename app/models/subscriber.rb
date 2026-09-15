# 週次メールの購読者。オーディエンスごとに1メールアドレス1件。
class Subscriber < ApplicationRecord
  # utm（流入元）は常にハッシュとして扱う
  attribute :utm, default: -> { {} }

  belongs_to :audience

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: "の形式が正しくありません" },
                    uniqueness: { scope: :audience_id, case_sensitive: false }

  normalizes :email, with: ->(email) { email.strip.downcase }

  scope :active, -> { where(unsubscribed_at: nil).where.not(confirmed_at: nil) }
end
