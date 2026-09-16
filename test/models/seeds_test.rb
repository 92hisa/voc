# このファイルは初期データ（db/seeds.rb）が何度流しても増えないことを確かめる。
require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "初期データは2回流しても増えない" do
    capture_io { Rails.application.load_seed }
    counts = [ Audience.count, AudienceQuery.for_source("threads").count ]

    capture_io { Rails.application.load_seed }

    assert_equal counts, [ Audience.count, AudienceQuery.for_source("threads").count ]
    assert Audience.find_by(slug: "web-seisaku").audience_queries.for_source("threads").active.any?
  end
end
