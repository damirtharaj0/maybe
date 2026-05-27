class Provider::YahooFinance < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)

  EXCHANGE_MIC_SUFFIX_MAP = {
    # US exchanges — no suffix
    "XNYS" => "",
    "XNAS" => "",
    "XASE" => "",
    "BATS" => "",
    # London Stock Exchange
    "XLON" => ".L",
    # Deutsche Börse (Frankfurt)
    "XETR" => ".DE",
    # Tokyo Stock Exchange
    "XTKS" => ".T",
    # Toronto Stock Exchange
    "XTSE" => ".TO",
    # Australian Securities Exchange
    "XASX" => ".AX",
    # Hong Kong Stock Exchange
    "XHKG" => ".HK",
    # Shanghai Stock Exchange
    "XSHG" => ".SS",
    # Shenzhen Stock Exchange
    "XSHE" => ".SZ",
    # Euronext Paris
    "XPAR" => ".PA",
    # Euronext Amsterdam
    "XAMS" => ".AS",
    # SIX Swiss Exchange
    "XSWX" => ".SW",
    # Borsa Italiana (Milan)
    "XMIL" => ".MI",
    # Bolsa de Madrid
    "XMAD" => ".MC",
    # Korea Exchange
    "XKRX" => ".KS",
    # Bombay Stock Exchange
    "XBOM" => ".BO",
    # National Stock Exchange of India
    "XNSE" => ".NS"
  }.freeze

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    raise NotImplementedError, "Provider::YahooFinance does not implement #search_securities yet"
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    raise NotImplementedError, "Provider::YahooFinance does not implement #fetch_security_info yet"
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    with_provider_response do
      response = fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date, end_date: date)
      raise response.error if !response.success?
      response.data.first
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    with_provider_response do
      ticker = ticker_for(symbol, exchange_operating_mic)

      # Split into year-sized chunks if range is large
      chunks = date_chunks(start_date, end_date)

      prices = chunks.flat_map do |chunk_start, chunk_end|
        fetch_prices_chunk(ticker, symbol, exchange_operating_mic, chunk_start, chunk_end)
      end

      prices
    end
  end

  private
    def date_chunks(start_date, end_date, chunk_size_days: 365)
      chunks = []
      current = start_date
      while current <= end_date
        chunk_end = [ current + chunk_size_days, end_date ].min
        chunks << [ current, chunk_end ]
        current = chunk_end + 1
      end
      chunks
    end

    def fetch_prices_chunk(ticker, symbol, exchange_operating_mic, start_date, end_date)
      period1 = start_date.to_time.to_i
      period2 = end_date.to_time.to_i

      response = client.get("/v8/finance/chart/#{ticker}") do |req|
        req.params["interval"] = "1d"
        req.params["period1"] = period1
        req.params["period2"] = period2
      end

      parsed = JSON.parse(response.body)
      result = parsed.dig("chart", "result")&.first

      return [] unless result

      timestamps = result["timestamp"] || []
      quotes = result.dig("indicators", "quote")&.first || {}
      closes = quotes["close"] || []
      opens = quotes["open"] || []
      currency = result.dig("meta", "currency") || "USD"

      timestamps.each_with_index.filter_map do |ts, i|
        price_value = closes[i] || opens[i]
        next unless price_value

        Price.new(
          symbol: symbol,
          date: Time.at(ts).to_date,
          price: price_value,
          currency: currency,
          exchange_operating_mic: exchange_operating_mic
        )
      end
    end

    def ticker_for(symbol, exchange_operating_mic)
      if EXCHANGE_MIC_SUFFIX_MAP.key?(exchange_operating_mic)
        "#{symbol}#{EXCHANGE_MIC_SUFFIX_MAP[exchange_operating_mic]}"
      else
        Rails.logger.warn("Provider::YahooFinance: unknown exchange MIC '#{exchange_operating_mic}' for symbol '#{symbol}', falling back to bare symbol")
        symbol
      end
    end

    def client
      @client ||= Faraday.new(url: "https://query1.finance.yahoo.com") do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
        faraday.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      end
    end
end
