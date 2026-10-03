import Foundation

/// One provider's dated product quote. Buy and sell refer to the dealer's side.
public struct GoldQuote: Codable, Equatable, Sendable {
    public let product: GoldProduct
    public let dealerBuy: Decimal
    public let dealerSell: Decimal
    public let observedAt: Date
    public let fetchedAt: Date
    public let productLabel: String

    public init(product: GoldProduct, dealerBuy: Decimal, dealerSell: Decimal,
                observedAt: Date, fetchedAt: Date, productLabel: String) {
        self.product = product
        self.dealerBuy = dealerBuy
        self.dealerSell = dealerSell
        self.observedAt = observedAt
        self.fetchedAt = fetchedAt
        self.productLabel = productLabel
    }

    public var sourceName: String { "Altınkaynak" }
    public var sourceURL: URL { GoldPriceStore.sourceURL }

    private enum CodingKeys: String, CodingKey {
        case product, dealerBuy, dealerSell, observedAt, fetchedAt, productLabel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        product = try values.decode(GoldProduct.self, forKey: .product)
        let buy = try values.decode(String.self, forKey: .dealerBuy)
        let sell = try values.decode(String.self, forKey: .dealerSell)
        guard let decodedBuy = GoldPriceNumber.cacheDecimal(buy),
              let decodedSell = GoldPriceNumber.cacheDecimal(sell) else {
            throw DecodingError.dataCorruptedError(forKey: .dealerBuy, in: values,
                                                   debugDescription: "Invalid decimal gold price")
        }
        dealerBuy = decodedBuy
        dealerSell = decodedSell
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        fetchedAt = try values.decode(Date.self, forKey: .fetchedAt)
        productLabel = try values.decode(String.self, forKey: .productLabel)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(product, forKey: .product)
        // Strings avoid introducing floating-point rounding in disk caches.
        try values.encode(NSDecimalNumber(decimal: dealerBuy).stringValue, forKey: .dealerBuy)
        try values.encode(NSDecimalNumber(decimal: dealerSell).stringValue, forKey: .dealerSell)
        try values.encode(observedAt, forKey: .observedAt)
        try values.encode(fetchedAt, forKey: .fetchedAt)
        try values.encode(productLabel, forKey: .productLabel)
    }
}

public struct GoldLookup: Equatable, Sendable {
    public let quote: GoldQuote
    /// True when a failed refresh uses a previously saved quote.
    public let usedOfflineCache: Bool
    public let failureDescription: String?

    public init(quote: GoldQuote, usedOfflineCache: Bool, failureDescription: String? = nil) {
        self.quote = quote
        self.usedOfflineCache = usedOfflineCache
        self.failureDescription = failureDescription
    }
}

public enum GoldPriceError: Error, LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidProduct(GoldProduct)
    case missingProduct(GoldProduct)
    case unavailable(GoldProduct, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The gold service returned an invalid price board."
        case .httpStatus(let status):
            return "The gold service could not provide prices (HTTP \(status))."
        case .invalidProduct(let product):
            return "The gold service returned an invalid \(product.providerName) quote."
        case .missingProduct(let product):
            return "The gold service did not include a \(product.providerName) quote."
        case .unavailable(let product, let reason):
            return "No saved \(product.providerName) quote is available. \(reason)"
        }
    }
}

/// Requests the public board only. Scratch contents and quantities never leave
/// the Mac. A single board request serves concurrent lookups for all products.
public actor GoldPriceStore {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public nonisolated static let sourceURL = URL(string: "https://static.altinkaynak.com/public/Gold")!
    public nonisolated static let providerURL = URL(string: "https://www.altinkaynak.com/Araclar/Servisler")!

    private struct Cache: Codable {
        let version: Int
        let quotes: [GoldQuote]
    }

    private struct Board: Sendable {
        var quotes: [GoldProduct: GoldQuote]
        var failures: [GoldProduct: String]
    }

    private struct Pending {
        let id: UUID
        let task: Task<Board, Error>
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
    private var quotes: [GoldProduct: GoldQuote]
    private var pending: Pending?
    private var failures: [GoldProduct: FailedAttempt] = [:]
    public private(set) var cacheWriteError: String?
    public private(set) var cacheReadError: String?

    public init(cacheURL: URL? = GoldPriceStore.defaultCacheURL,
                refreshInterval: TimeInterval = 60, retryInterval: TimeInterval = 60,
                loader: @escaping Loader = { try await GoldPriceStore.load($0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheURL = cacheURL
        self.refreshInterval = max(0, refreshInterval)
        self.retryInterval = max(0, retryInterval)
        self.loader = loader
        self.now = now
        let cache = Self.readCache(at: cacheURL, now: now())
        quotes = cache.quotes
        cacheReadError = cache.error
    }

    public nonisolated static var defaultCacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Bobby", isDirectory: true)
            .appendingPathComponent("gold-prices.json")
    }

    public func cachedQuote(for product: GoldProduct) -> GoldQuote? { quotes[product] }

    public func quote(for product: GoldProduct, forceRefresh: Bool = false) async throws -> GoldQuote {
        try await lookup(for: product, forceRefresh: forceRefresh).quote
    }

    public func lookup(for product: GoldProduct, forceRefresh: Bool = false) async throws -> GoldLookup {
        let date = now()
        // An unavailable board, or one missing this product, must not trigger a
        // fresh network request for every keystroke or every other product.
        if !forceRefresh, let failed = failures[product], date >= failed.date,
           date.timeIntervalSince(failed.date) < retryInterval {
            return try fallback(for: product, reason: failed.reason)
        }
        if !forceRefresh, failures[product] == nil, let cached = quotes[product], date >= cached.fetchedAt,
           date.timeIntervalSince(cached.fetchedAt) < refreshInterval {
            return GoldLookup(quote: cached, usedOfflineCache: false)
        }

        let request: Pending
        if let pending {
            request = pending
        } else {
            let loader = self.loader
            let now = self.now
            request = Pending(id: UUID(), task: Task {
                try await Self.fetch(loader: loader, fetchedAt: now)
            })
            pending = request
        }

        let board: Board
        do {
            board = try await request.task.value
        } catch {
            let reason = Self.reason(for: error)
            if pending?.id == request.id {
                pending = nil
                let failedAt = now()
                for product in Self.products {
                    failures[product] = FailedAttempt(date: failedAt, reason: reason)
                }
            }
            return try fallback(for: product, reason: reason)
        }

        if pending?.id == request.id {
            pending = nil
            let completedAt = now()
            for product in Self.products {
                if let quote = board.quotes[product] {
                    quotes[product] = quote
                    failures.removeValue(forKey: product)
                } else {
                    failures[product] = FailedAttempt(date: completedAt,
                        reason: board.failures[product] ?? GoldPriceError.missingProduct(product).localizedDescription)
                }
            }
            if !board.quotes.isEmpty { persistCache() }
        }

        if let quote = board.quotes[product] {
            return GoldLookup(quote: quote, usedOfflineCache: false)
        }
        return try fallback(for: product,
            reason: board.failures[product] ?? GoldPriceError.missingProduct(product).localizedDescription)
    }

    public nonisolated static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GoldPriceError.invalidResponse }
        return (data, response)
    }

    private func fallback(for product: GoldProduct, reason: String) throws -> GoldLookup {
        if let cached = quotes[product] {
            return GoldLookup(quote: cached, usedOfflineCache: true, failureDescription: reason)
        }
        throw GoldPriceError.unavailable(product, reason)
    }

    private nonisolated static let products: [GoldProduct] = [
        .quarterCoin, .oldQuarterCoin, .halfCoin, .oldHalfCoin,
        .fullCoin, .oldFullCoin, .ataCoin, .gram
    ]

    private nonisolated static func fetch(loader: Loader,
                                         fetchedAt: @Sendable () -> Date) async throws -> Board {
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await loader(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoldPriceError.httpStatus(response.statusCode)
        }
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw GoldPriceError.invalidResponse
        }
        let date = fetchedAt()
        var board = Board(quotes: [:], failures: [:])
        var seen: Set<GoldProduct> = []
        for rawRow in rows {
            guard let row = rawRow as? [String: Any], let code = row["Kod"] as? String,
                  let product = GoldProduct(rawValue: code) else { continue }
            // Even an invalid earlier row makes a repeated product ambiguous.
            guard seen.insert(product).inserted else {
                board.quotes.removeValue(forKey: product)
                board.failures[product] = GoldPriceError.invalidProduct(product).localizedDescription
                continue
            }
            guard let buyText = row["Alis"] as? String, let sellText = row["Satis"] as? String,
                  let buy = GoldPriceNumber.providerDecimal(buyText),
                  let sell = GoldPriceNumber.providerDecimal(sellText),
                  buy > 0, sell > 0, buy <= sell,
                  let timestamp = row["GuncellenmeZamani"] as? String,
                  let observation = GoldPriceDate.parse(timestamp),
                  observation <= date.addingTimeInterval(5 * 60),
                  let label = row["Aciklama"] as? String,
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                board.failures[product] = GoldPriceError.invalidProduct(product).localizedDescription
                continue
            }
            board.quotes[product] = GoldQuote(product: product, dealerBuy: buy, dealerSell: sell,
                                            observedAt: observation, fetchedAt: date, productLabel: label)
        }
        return board
    }

    private func persistCache() {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let cache = Cache(version: 1, quotes: quotes.values.sorted { $0.product.rawValue < $1.product.rawValue })
            try encoder.encode(cache).write(to: cacheURL, options: .atomic)
            cacheWriteError = nil
        } catch {
            cacheWriteError = "Gold prices are available for this session, but their cache could not be saved."
        }
    }

    private nonisolated static func readCache(at url: URL?, now: Date)
        -> (quotes: [GoldProduct: GoldQuote], error: String?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
        do {
            let data = try Data(contentsOf: url)
            let cache = try JSONDecoder().decode(Cache.self, from: data)
            guard cache.version == 1 else { throw GoldPriceError.invalidResponse }
            var result: [GoldProduct: GoldQuote] = [:]
            for quote in cache.quotes {
                guard valid(quote, at: now), result[quote.product] == nil else {
                    throw GoldPriceError.invalidResponse
                }
                result[quote.product] = quote
            }
            return (result, nil)
        } catch {
            // Reading is side-effect free. In particular, never replace a
            // corrupt or newer-version cache during initialization.
            return ([:], "The saved gold-price cache could not be read.")
        }
    }

    private nonisolated static func valid(_ quote: GoldQuote, at date: Date) -> Bool {
        !quote.dealerBuy.isNaN && !quote.dealerSell.isNaN
            && quote.dealerBuy > 0 && quote.dealerSell > 0 && quote.dealerBuy <= quote.dealerSell
            && quote.observedAt.timeIntervalSinceReferenceDate.isFinite
            && quote.fetchedAt.timeIntervalSinceReferenceDate.isFinite
            && quote.observedAt <= date.addingTimeInterval(5 * 60)
            && quote.fetchedAt <= date.addingTimeInterval(5 * 60)
            && quote.observedAt <= quote.fetchedAt.addingTimeInterval(5 * 60)
            && !quote.productLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private nonisolated static func reason(for error: Error) -> String {
        if let typed = error as? GoldPriceError { return typed.localizedDescription }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
                return "The gold service is unreachable. Connect to the internet and try again."
            default: break
            }
        }
        return "The gold service is unavailable. Try refreshing again later."
    }
}

private enum GoldPriceNumber {
    static func providerDecimal(_ text: String) -> Decimal? {
        // This is the feed's Turkish format, independent of scratch syntax.
        // A dot is valid only as a full three-digit grouping separator.
        guard text.range(of: "^(?:[0-9]+|[1-9][0-9]{0,2}(?:\\.[0-9]{3})+)(?:,[0-9]+)?$",
                         options: .regularExpression) != nil else { return nil }
        return cacheDecimal(text.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "."))
    }

    static func cacheDecimal(_ text: String) -> Decimal? {
        guard text.count <= 128,
              text.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN,
              normalized(text) == normalized(NSDecimalNumber(decimal: value).stringValue) else { return nil }
        return value
    }

    private static func normalized(_ text: String) -> String {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let integer = pieces[0].drop(while: { $0 == "0" })
        let whole = integer.isEmpty ? "0" : String(integer)
        guard pieces.count == 2 else { return whole }
        let fractional = pieces[1].reversed().drop(while: { $0 == "0" }).reversed()
        return fractional.isEmpty ? whole : whole + "." + String(fractional)
    }
}

private enum GoldPriceDate {
    static func parse(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count == 19, bytes[2] == 46, bytes[5] == 46, bytes[10] == 32,
              bytes[13] == 58, bytes[16] == 58,
              bytes.enumerated().allSatisfy({ [2, 5, 10, 13, 16].contains($0.offset) || (48...57).contains($0.element) })
        else { return nil }
        func number(_ range: Range<Int>) -> Int { Int(String(decoding: bytes[range], as: UTF8.self))! }
        let day = number(0..<2), month = number(3..<5), year = number(6..<10)
        let hour = number(11..<13), minute = number(14..<16), second = number(17..<19)
        guard year > 0, (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              roundTrip.hour == hour, roundTrip.minute == minute, roundTrip.second == second else { return nil }
        return date
    }
}
