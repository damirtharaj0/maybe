class Provider::TwelveData < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)

  BASE_URL = "https://api.twelvedata.com"

  INSTRUMENT_TYPE_MAP = {
    "Common Stock" => "common stock",
    "ETF" => "etf",
    "Mutual Fund" => "mutual fund",
    "Index" => "index"
  }.freeze

  def initialize(api_key)
    @api_key = api_key
  end

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      response = client.get("/symbol_search") do |req|
        req.params["symbol"] = symbol
        req.params["outputsize"] = 30
      end

      parsed = JSON.parse(response.body)

      (parsed["data"] || []).map do |item|
        Security.new(
          symbol: item["symbol"],
          name: item["instrument_name"],
          logo_url: nil,
          exchange_operating_mic: item["mic_code"],
          country_code: item["country"]
        )
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      profile_response = client.get("/profile") do |req|
        req.params["symbol"] = symbol
        req.params["mic_code"] = exchange_operating_mic if exchange_operating_mic.present?
      end

      logo_response = client.get("/logo") do |req|
        req.params["symbol"] = symbol
      end

      profile = JSON.parse(profile_response.body)
      logo = JSON.parse(logo_response.body)

      SecurityInfo.new(
        symbol: symbol,
        name: profile["name"],
        logo_url: logo["url"],
        description: profile["description"],
        kind: INSTRUMENT_TYPE_MAP[profile["type"]] || profile["type"]&.downcase,
        links: nil,
        exchange_operating_mic: exchange_operating_mic
      )
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    with_provider_response do
      prices = fetch_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date, end_date: date)
      prices.first
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    with_provider_response do
      fetch_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: start_date, end_date: end_date)
    end
  end

  private
    attr_reader :api_key

    def fetch_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
      response = client.get("/time_series") do |req|
        req.params["symbol"] = symbol
        req.params["interval"] = "1day"
        req.params["start_date"] = start_date.to_s
        req.params["end_date"] = end_date.to_s
        req.params["mic_code"] = exchange_operating_mic if exchange_operating_mic.present?
        req.params["outputsize"] = 5000
        req.params["order"] = "ASC"
      end

      parsed = JSON.parse(response.body)
      meta = parsed["meta"] || {}
      values = parsed["values"] || []

      currency = meta["currency"] || "USD"
      mic = meta["mic_code"] || exchange_operating_mic

      values.filter_map do |entry|
        next if entry["close"].blank?

        Price.new(
          symbol: symbol,
          date: Date.parse(entry["datetime"]),
          price: entry["close"].to_f,
          currency: currency,
          exchange_operating_mic: mic
        )
      end
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })
        faraday.response :raise_error
        faraday.params["apikey"] = api_key
      end
    end
end
