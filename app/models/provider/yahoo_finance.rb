class Provider::YahooFinance < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)

  YAHOO_EXCHANGE_TO_MIC = {
    "NMS" => "XNAS",
    "NGM" => "XNAS",
    "NCM" => "XNAS",
    "NYQ" => "XNYS",
    "PCX" => "ARCX",
    "ASE" => "XASE",
    "LSE" => "XLON",
    "FRA" => "XETR",
    "TKS" => "XTKS",
    "TSX" => "XTSE",
    "ASX" => "XASX",
    "HKG" => "XHKG",
    "SHH" => "XSHG",
    "SHZ" => "XSHE",
    "PAR" => "XPAR",
    "AMS" => "XAMS",
    "SWX" => "XSWX",
    "MIL" => "XMIL",
    "MAD" => "XMAD",
    "KSC" => "XKRX",
    "BSE" => "XBOM",
    "NSE" => "XNSE"
  }.freeze

  YAHOO_QUOTE_TYPE_TO_KIND = {
    "EQUITY" => "common stock",
    "ETF" => "etf",
    "MUTUALFUND" => "mutual fund"
  }.freeze

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
    with_provider_response do
      response = client.get("/v1/finance/search") do |req|
        req.params["q"] = symbol
        req.params["quotesCount"] = 25
        req.params["lang"] = "en-US"
      end

      parsed = JSON.parse(response.body)
      quotes = parsed.dig("finance", "result", 0, "quotes") || parsed["quotes"] || []

      quotes.map do |quote|
        exchange_code = quote["exchange"]
        mic = YAHOO_EXCHANGE_TO_MIC[exchange_code]

        Security.new(
          symbol: quote["symbol"],
          name: quote["shortname"] || quote["longname"],
          logo_url: nil,
          exchange_operating_mic: mic,
          country_code: nil
        )
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      ticker = ticker_for(symbol, exchange_operating_mic)

      response = client.get("/v10/finance/quoteSummary/#{ticker}") do |req|
        req.params["modules"] = "assetProfile,quoteType,summaryProfile"
      end

      parsed = JSON.parse(response.body)
      result = parsed.dig("quoteSummary", "result")&.first

      asset_profile = result&.dig("assetProfile") || {}
      quote_type = result&.dig("quoteType") || {}

      raw_kind = quote_type["quoteType"]
      kind = YAHOO_QUOTE_TYPE_TO_KIND[raw_kind] || raw_kind&.downcase

      SecurityInfo.new(
        symbol: quote_type["symbol"] || symbol,
        name: quote_type["longName"] || quote_type["shortName"],
        logo_url: nil,
        description: asset_profile["longBusinessSummary"],
        kind: kind,
        links: nil,
        exchange_operating_mic: exchange_operating_mic
      )
    end
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
