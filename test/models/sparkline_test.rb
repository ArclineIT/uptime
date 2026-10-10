require "test_helper"

class SparklineTest < ActiveSupport::TestCase
  Point = Struct.new(:response_ms, :up) { alias_method :up?, :up }

  test "plots oldest to newest, scaled to the slowest check" do
    # Newest first, as the database returns them.
    sparkline = Sparkline.new(nil, [ Point.new(50, true), Point.new(0, false), Point.new(100, true) ])

    assert_equal "0,5 200,55 400,30", sparkline.points
    assert_equal [ 200 ], sparkline.down_xs
    assert_equal 100, sparkline.max_ms
    assert_equal 50.0, sparkline.avg_ms
  end

  test "handles one check, all-zero times and no checks" do
    assert_equal "0,5", Sparkline.new(nil, [ Point.new(80, true) ]).points
    assert_equal "0,55 400,55", Sparkline.new(nil, [ Point.new(0, false), Point.new(0, false) ]).points
    assert Sparkline.new(nil, []).empty?
    assert_equal 0, Sparkline.new(nil, []).avg_ms
  end
end
