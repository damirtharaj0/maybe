require "test_helper"

class Provider::YahooFinanceTest < ActiveSupport::TestCase
  setup do
    @subject = Provider::YahooFinance.new
  end

  test "fetches security price" do
    aapl = securities(:aapl)

    VCR.use_cassette("yahoo_finance/security_price") do
      response = @subject.fetch_security_price(
        symbol: aapl.ticker,
        exchange_operating_mic: aapl.exchange_operating_mic,
        date: Date.iso8601("2024-08-01")
      )

      assert response.success?
      assert response.data.present?
      assert response.data.date.is_a?(Date)
    end
  end

  test "fetches security prices" do
    aapl = securities(:aapl)

    VCR.use_cassette("yahoo_finance/security_prices") do
      response = @subject.fetch_security_prices(
        symbol: aapl.ticker,
        exchange_operating_mic: aapl.exchange_operating_mic,
        start_date: Date.iso8601("2024-01-01"),
        end_date: Date.iso8601("2024-08-01")
      )

      assert response.success?
      assert response.data.first.date.is_a?(Date)
      assert response.data.count > 0
    end
  end
end
