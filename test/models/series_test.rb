require "test_helper"

class SeriesTest < ActiveSupport::TestCase
  def build_series(extra_args = {})
    values = 3.times.map do |i|
      date = Date.current + i.days
      Series::Value.new(
        date: date,
        date_formatted: I18n.l(date, format: :long),
        value: 100 + i * 10,
        trend: Trend.new(current: 100 + i * 10, previous: i == 0 ? nil : 100 + (i - 1) * 10)
      )
    end

    Series.new(
      start_date: Date.current,
      end_date: Date.current + 2.days,
      interval: "1 day",
      values: values,
      **extra_args
    )
  end

  test "as_json omits projected_start_date when not set" do
    series = build_series
    json = series.as_json
    assert_not json.key?(:projected_start_date)
  end

  test "as_json includes projected_start_date when set" do
    today = Date.current
    series = build_series(projected_start_date: today)
    json = series.as_json
    assert json.key?(:projected_start_date)
    assert_equal today, json[:projected_start_date]
  end

  test "projected_start_date defaults to nil" do
    series = build_series
    assert_nil series.projected_start_date
  end

  test "months_of_data defaults to nil" do
    series = build_series
    assert_nil series.months_of_data
  end

  test "months_of_data is accessible when set" do
    series = build_series(months_of_data: 6)
    assert_equal 6, series.months_of_data
  end
end
