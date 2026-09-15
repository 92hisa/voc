# このファイルはオーディエンス1つ・媒体1つ分の収集を実行する。
# 媒体ごとの処理は app/services/sources/ のクラスに任せ、ここは振り分けだけ。
class CollectJob < ApplicationJob
  queue_as :default

  def perform(slug, source, days = 7)
    audience = Audience.find_by!(slug: slug)

    source_object =
      case source.to_s
      when "youtube" then Sources::YoutubeSource.new(audience: audience, days: days.to_i)
      when "bluesky" then Sources::BlueskySource.new(audience: audience, days: days.to_i)
      else raise ArgumentError, "未対応の媒体です: #{source}（今使えるのは youtube / bluesky）"
      end

    source_object.collect
  end
end
