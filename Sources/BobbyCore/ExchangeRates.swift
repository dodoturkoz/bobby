import Foundation

/// A dated reference quote, kept separate from the user's calculation text.
public struct ExchangeQuote: Sendable, Codable, Equatable {
    public let pair: CurrencyPair
    public let rate: Decimal
    public let observedDate: String
    public let fetchedAt: Date
    public let providers: [String]

    public init(pair: CurrencyPair, rate: Decimal, observedDate: String,
                fetchedAt: Date, providers: [String]) {
        self.pair = CurrencyPair(base: pair.base, quote: pair.quote)
        self.rate = rate
        self.observedDate = observedDate
        self.fetchedAt = fetchedAt
        self.providers = Array(Set(providers)).sorted()
    }

    public var rateType: String {
        pair.base == pair.quote ? "Same currency" : "Blended mid-market reference"
    }

    public var sourceLabel: String {
        guard pair.base != pair.quote else { return "Identity rate" }
        return providers.isEmpty ? "Frankfurter" : "Frankfurter · " + providers.joined(separator: ", ")
    }

    /// An earlier observation is normal on weekends and holidays. Show its date
    /// neutrally rather than treating this property as a provider-failure alert.
    public var isStale: Bool { isStale(at: Date()) }

    public func isStale(at date: Date) -> Bool {
        pair.base != pair.quote && observedDate < RateDate.string(from: date)
    }

    // Store Decimal as a string in our cache so a cache round-trip never depends
    // on floating-point JSON serialization. CurrencyPair need not be Codable.
    private enum CodingKeys: String, CodingKey {
        case base, quote, rate, observedDate, fetchedAt, providers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pair = CurrencyPair(base: try values.decode(String.self, forKey: .base),
                            quote: try values.decode(String.self, forKey: .quote))
        let decimalText = try values.decode(String.self, forKey: .rate)
        guard let decodedRate = Decimal(string: decimalText, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: .rate, in: values, debugDescription: "Invalid decimal rate")
        }
        rate = decodedRate
        observedDate = try values.decode(String.self, forKey: .observedDate)
        fetchedAt = try values.decode(Date.self, forKey: .fetchedAt)
        providers = try values.decode([String].self, forKey: .providers)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pair.base, forKey: .base)
        try values.encode(pair.quote, forKey: .quote)
        try values.encode(NSDecimalNumber(decimal: rate).stringValue, forKey: .rate)
        try values.encode(observedDate, forKey: .observedDate)
        try values.encode(fetchedAt, forKey: .fetchedAt)
        try values.encode(providers, forKey: .providers)
    }
}

public struct RateLookup: Sendable, Equatable {
    public let quote: ExchangeQuote
    /// True when refreshing failed and this response uses the saved quote.
    /// A service failure can trigger this fallback even while the Mac is online.
    public let usedOfflineCache: Bool
    public let failureDescription: String?

    public init(quote: ExchangeQuote, usedOfflineCache: Bool, failureDescription: String? = nil) {
        self.quote = quote
        self.usedOfflineCache = usedOfflineCache
        self.failureDescription = failureDescription
    }
}

public enum ExchangeRateError: Error, LocalizedError, Sendable, Equatable {
    case invalidCurrency
    case invalidResponse
    case httpStatus(Int)
    case unavailable(CurrencyPair, String)

    public var errorDescription: String? {
        switch self {
        case .invalidCurrency:
            return "Use a three-letter currency code, or TL for Turkish lira."
        case .invalidResponse:
            return "The rate service returned an invalid quote."
        case .httpStatus(let status):
            return "The rate service could not provide this quote (HTTP \(status))."
        case .unavailable(let pair, let reason):
            return "No saved \(pair.base)/\(pair.quote) rate is available. \(reason)"
        }
    }
}

/// Fetches only a currency pair, never scratch contents or principal amounts.
public actor ExchangeRateStore {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct Cache: Codable {
        let version: Int
        let quotes: [ExchangeQuote]
    }

    private struct Pending {
        let id: UUID
        let task: Task<ExchangeQuote, Error>
    }

    private struct FailedAttempt {
        let date: Date
        let reason: String
    }

    private let cacheURL: URL?
    private let refreshInterval: TimeInterval
    private let retryInterval: TimeInterval
    private let loader: Loader
    private let now: @Sendable () -> Date
    private var quotes: [String: ExchangeQuote]
    private var pending: [String: Pending] = [:]
    private var failures: [String: FailedAttempt] = [:]
    public private(set) var cacheWriteError: String?

    /// Pass nil to keep a memory-only cache. Production callers supply a URL
    /// beside their scratch store, or use `defaultCacheURL`.
    public init(cacheURL: URL? = ExchangeRateStore.defaultCacheURL,
                refreshInterval: TimeInterval = 6 * 60 * 60,
                retryInterval: TimeInterval = 60,
                loader: @escaping Loader = { try await ExchangeRateStore.load($0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheURL = cacheURL
        self.refreshInterval = max(0, refreshInterval)
        self.retryInterval = max(0, retryInterval)
        self.loader = loader
        self.now = now
        self.quotes = Self.readCache(at: cacheURL)
    }

    public nonisolated static var defaultCacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Bobby", isDirectory: true)
            .appendingPathComponent("exchange-rates.json")
    }

    public func cachedQuote(for pair: CurrencyPair) -> ExchangeQuote? {
        let normalized = Self.normalize(pair)
        guard Self.validPair(normalized) else { return nil }
        if normalized.base == normalized.quote { return Self.identity(normalized, at: now()) }
        return quotes[Self.key(normalized)]
    }

    public func quote(for pair: CurrencyPair, forceRefresh: Bool = false) async throws -> ExchangeQuote {
        try await lookup(for: pair, forceRefresh: forceRefresh).quote
    }

    public func lookup(for pair: CurrencyPair, forceRefresh: Bool = false) async throws -> RateLookup {
        let normalized = Self.normalize(pair)
        guard Self.validPair(normalized) else { throw ExchangeRateError.invalidCurrency }
        let date = now()
        if normalized.base == normalized.quote {
            return RateLookup(quote: Self.identity(normalized, at: date), usedOfflineCache: false)
        }
        let key = Self.key(normalized)

        // Edits on an offline scratch must not create a request per keystroke.
        if !forceRefresh, let failed = failures[key], date >= failed.date,
           date.timeIntervalSince(failed.date) < retryInterval {
            if let cached = quotes[key] {
                return RateLookup(quote: cached, usedOfflineCache: true,
                                  failureDescription: failed.reason)
            }
            throw ExchangeRateError.unavailable(normalized, failed.reason)
        }
        if !forceRefresh, failures[key] == nil, let cached = quotes[key], date >= cached.fetchedAt,
           date.timeIntervalSince(cached.fetchedAt) < refreshInterval {
            return RateLookup(quote: cached, usedOfflineCache: false)
        }

        let request: Pending
        if let existing = pending[key] {
            request = existing
        } else {
            let loader = self.loader
            let now = self.now
            request = Pending(id: UUID(), task: Task {
                try await Self.fetch(normalized, loader: loader, fetchedAt: now)
            })
            pending[key] = request
        }

        do {
            let quote = try await request.task.value
            if pending[key]?.id == request.id {
                pending.removeValue(forKey: key)
                failures.removeValue(forKey: key)
                quotes[key] = quote
                persistCache()
            }
            return RateLookup(quote: quote, usedOfflineCache: false)
        } catch {
            let reason = Self.reason(for: error)
            if pending[key]?.id == request.id {
                pending.removeValue(forKey: key)
                failures[key] = FailedAttempt(date: now(), reason: reason)
            }
            if let cached = quotes[key] {
                return RateLookup(quote: cached, usedOfflineCache: true,
                                  failureDescription: reason)
            }
            throw ExchangeRateError.unavailable(normalized, reason)
        }
    }

    public nonisolated static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ExchangeRateError.invalidResponse }
        return (data, response)
    }

    private nonisolated static func fetch(_ pair: CurrencyPair, loader: Loader,
                                         fetchedAt: @Sendable () -> Date) async throws -> ExchangeQuote {
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        components.queryItems = [URLQueryItem(name: "base", value: pair.base),
                                 URLQueryItem(name: "quotes", value: pair.quote),
                                 URLQueryItem(name: "expand", value: "providers")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await loader(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ExchangeRateError.httpStatus(response.statusCode)
        }
        let rows: [ProviderQuote]
        do { rows = try JSONDecoder().decode([ProviderQuote].self, from: data) }
        catch { throw ExchangeRateError.invalidResponse }
        guard rows.count == 1, let row = rows.first,
              normalize(CurrencyPair(base: row.base, quote: row.quote)) == pair,
              !row.rate.isNaN, row.rate > 0, RateDate.isValid(row.date) else {
            throw ExchangeRateError.invalidResponse
        }
        return ExchangeQuote(pair: pair, rate: row.rate, observedDate: row.date,
                             fetchedAt: fetchedAt(), providers: row.providers)
    }

    private func persistCache() {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let cache = Cache(version: 1, quotes: quotes.values.sorted { Self.key($0.pair) < Self.key($1.pair) })
            try encoder.encode(cache).write(to: cacheURL, options: .atomic)
            cacheWriteError = nil
        } catch {
            cacheWriteError = "The rate is available for this session, but its cache could not be saved."
        }
    }

    private nonisolated static func readCache(at url: URL?) -> [String: ExchangeQuote] {
        guard let url, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.version == 1 else { return [:] }
        var result: [String: ExchangeQuote] = [:]
        for quote in cache.quotes where validPair(quote.pair) && !quote.rate.isNaN && quote.rate > 0
            && RateDate.isValid(quote.observedDate) {
            let key = key(quote.pair)
            if let previous = result[key], previous.fetchedAt >= quote.fetchedAt { continue }
            result[key] = quote
        }
        return result
    }

    private nonisolated static func normalize(_ pair: CurrencyPair) -> CurrencyPair {
        CurrencyPair(base: pair.base, quote: pair.quote)
    }

    private nonisolated static func validPair(_ pair: CurrencyPair) -> Bool {
        [pair.base, pair.quote].allSatisfy { code in
            code.utf8.count == 3 && code.utf8.allSatisfy { (65...90).contains($0) }
        }
    }

    private nonisolated static func key(_ pair: CurrencyPair) -> String { pair.base + "/" + pair.quote }

    private nonisolated static func identity(_ pair: CurrencyPair, at date: Date) -> ExchangeQuote {
        ExchangeQuote(pair: pair, rate: 1, observedDate: RateDate.string(from: date), fetchedAt: date, providers: [])
    }

    private nonisolated static func reason(for error: Error) -> String {
        if let typed = error as? ExchangeRateError { return typed.localizedDescription }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
                return "The rate service is unreachable. Connect to the internet and try again."
            default: break
            }
        }
        return "The rate service is unavailable. Try refreshing again later."
    }
}

private struct ProviderQuote: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
    let providers: [String]

    private enum CodingKeys: String, CodingKey { case date, base, quote, rate, providers }
    private struct Contribution: Decodable {
        let key: String
        let excluded: Bool?
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(String.self, forKey: .date)
        base = try values.decode(String.self, forKey: .base)
        quote = try values.decode(String.self, forKey: .quote)
        rate = try values.decode(Decimal.self, forKey: .rate)
        if !values.contains(.providers) {
            providers = [] // Synthesized currency-peg records have no provider field.
        } else if let keys = try? values.decode([String].self, forKey: .providers) {
            providers = keys
        } else {
            providers = try values.decode([Contribution].self, forKey: .providers)
                .filter { $0.excluded != true }.map(\.key)
        }
    }
}

private enum RateDate {
    static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func isValid(_ text: String) -> Bool {
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
              year > 0, (1...12).contains(month), (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        return string(from: date) == text
    }
}
