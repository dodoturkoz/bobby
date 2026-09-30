import Foundation
import XCTest
@testable import BobbyCore

final class ExchangeRatesTests: XCTestCase {
    private let pair = CurrencyPair(base: "USD", quote: "TRY")
    private let instant = Date(timeIntervalSince1970: 1_790_769_600) // 2026-09-30 UTC

    func testReferenceQuotePreservesDecimalAndContributingProviders() async throws {
        let transport = MockRateTransport(data: Self.response(rate: "40.1234567890123456789"))
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { self.instant })
        let result = try await store.lookup(for: CurrencyPair(base: "usd", quote: "tl"))

        XCTAssertEqual(result.quote.pair, pair)
        XCTAssertEqual(result.quote.rate, Decimal(string: "40.1234567890123456789"))
        XCTAssertEqual(result.quote.observedDate, "2026-09-29")
        XCTAssertEqual(result.quote.providers, ["ECB", "TCMB"])
        XCTAssertEqual(result.quote.rateType, "Blended mid-market reference")
        XCTAssertEqual(result.quote.sourceLabel, "Frankfurter · ECB, TCMB")
        XCTAssertTrue(result.quote.isStale(at: instant))
        XCTAssertFalse(result.usedOfflineCache)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let url = try XCTUnwrap(requests.first?.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.path, "/v2/rates")
        XCTAssertTrue(query.contains(URLQueryItem(name: "base", value: "USD")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "quotes", value: "TRY")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "expand", value: "providers")))
    }

    func testTLAsSourceIsNormalizedBeforeRequest() async throws {
        let transport = MockRateTransport(data: Self.response(base: "TRY", quote: "USD", rate: "0.02"))
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
        let result = try await store.lookup(for: CurrencyPair(base: "tl", quote: "usd"))
        XCTAssertEqual(result.quote.pair.base, "TRY")
        let request = await transport.requests.first
        XCTAssertTrue(request?.url?.absoluteString.contains("base=TRY") == true)
    }

    func testSameCurrencyNeverNeedsNetwork() async throws {
        let transport = MockRateTransport(data: Data(), offline: true)
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { self.instant })
        let result = try await store.lookup(for: CurrencyPair(base: "TL", quote: "try"), forceRefresh: true)
        let cachedIdentity = await store.cachedQuote(for: CurrencyPair(base: "TRY", quote: "TL"))
        XCTAssertEqual(result.quote.rate, 1)
        XCTAssertEqual(result.quote.observedDate, "2026-09-30")
        XCTAssertEqual(cachedIdentity, result.quote)
        XCTAssertEqual(result.quote.sourceLabel, "Identity rate")
        XCTAssertFalse(result.quote.isStale(at: instant.addingTimeInterval(10 * 86400)))
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testFreshCacheAvoidsRefetchOnEveryEdit() async throws {
        let transport = MockRateTransport(data: Self.response())
        let clock = RateTestClock(instant)
        let store = ExchangeRateStore(cacheURL: nil, refreshInterval: 3600,
                                      loader: { try await transport.load($0) }, now: { clock.value })
        _ = try await store.lookup(for: pair)
        clock.advance(3599)
        for _ in 0..<10 { _ = try await store.lookup(for: pair) }
        var count = await transport.requests.count
        XCTAssertEqual(count, 1)
        clock.advance(1)
        _ = try await store.lookup(for: pair)
        count = await transport.requests.count
        XCTAssertEqual(count, 2)
        _ = try await store.lookup(for: pair, forceRefresh: true)
        count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testOfflineFallbackHasDateAndBriefRetryCooldown() async throws {
        let transport = MockRateTransport(data: Self.response())
        let clock = RateTestClock(instant)
        let store = ExchangeRateStore(cacheURL: nil, refreshInterval: 10, retryInterval: 60,
                                      loader: { try await transport.load($0) }, now: { clock.value })
        let original = try await store.lookup(for: pair)
        clock.advance(11)
        await transport.setOffline(true)
        let offline = try await store.lookup(for: pair)
        XCTAssertEqual(offline.quote, original.quote)
        XCTAssertTrue(offline.usedOfflineCache)
        XCTAssertNotNil(offline.failureDescription)
        XCTAssertEqual(offline.quote.observedDate, "2026-09-29")
        _ = try await store.lookup(for: pair)
        var count = await transport.requests.count
        XCTAssertEqual(count, 2)
        clock.advance(60)
        await transport.setOffline(false)
        let restored = try await store.lookup(for: pair)
        XCTAssertFalse(restored.usedOfflineCache)
        XCTAssertEqual(restored.quote.fetchedAt, clock.value)
        count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testNoCacheOfflineThrowsUsefulErrorAndSuppressesRepeatedRequests() async throws {
        let transport = MockRateTransport(data: Data(), offline: true)
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { self.instant })
        for _ in 0..<2 {
            do {
                _ = try await store.lookup(for: pair)
                XCTFail("A missing quote must not fabricate a rate")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("No saved USD/TRY rate"))
                XCTAssertTrue(error.localizedDescription.contains("internet"))
            }
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        let missing = await store.cachedQuote(for: pair)
        XCTAssertNil(missing)
    }

    func testConcurrentRequestsShareOneFetch() async throws {
        let transport = MockRateTransport(data: Self.response(), delayNanoseconds: 30_000_000)
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
        let results = try await withThrowingTaskGroup(of: ExchangeQuote.self) { group in
            for _ in 0..<20 { group.addTask { try await store.quote(for: self.pair) } }
            var values: [ExchangeQuote] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { $0 == results.first })
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testDiskCacheRoundTripRemainsAvailableOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rates.json")
        let transport = MockRateTransport(data: Self.response(rate: "40.1234567890123456789"))
        let first = ExchangeRateStore(cacheURL: url, loader: { try await transport.load($0) }, now: { self.instant })
        let fetched = try await first.quote(for: pair)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let offline = MockRateTransport(data: Data(), offline: true)
        let restart = ExchangeRateStore(cacheURL: url, loader: { try await offline.load($0) },
                                        now: { self.instant.addingTimeInterval(86400) })
        let saved = await restart.cachedQuote(for: pair)
        XCTAssertEqual(saved, fetched)
        let result = try await restart.lookup(for: pair)
        XCTAssertTrue(result.usedOfflineCache)
        XCTAssertEqual(result.quote.rate, Decimal(string: "40.1234567890123456789"))
    }

    func testCorruptOrUnsupportedCacheIsIgnoredWithoutChangingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rates.json")
        for invalid in [Data("broken json".utf8), Data("{\"version\":2,\"quotes\":[]}".utf8)] {
            try invalid.write(to: url)
            let store = ExchangeRateStore(cacheURL: url, loader: { _ in throw URLError(.notConnectedToInternet) })
            let quote = await store.cachedQuote(for: pair)
            XCTAssertNil(quote)
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    func testMalformedOrInvalidProviderRatesCannotEnterCache() async throws {
        let payloads = [Self.response(rate: "0"), Self.response(rate: "-1"),
                        Self.response(base: "EUR"), Self.response(date: "2026-02-30"),
                        Data("[]".utf8), Data("{\"rate\":123}".utf8), Data("bad json".utf8)]
        for payload in payloads {
            let transport = MockRateTransport(data: payload)
            let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
            do {
                _ = try await store.lookup(for: pair)
                XCTFail("Invalid response should not produce a quote")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid quote"))
            }
            let cached = await store.cachedQuote(for: pair)
            XCTAssertNil(cached)
        }
    }

    func testHTTPFailureIsVisibleAndCanUseLastReferenceQuote() async throws {
        let transport = MockRateTransport(data: Self.response())
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
        let first = try await store.quote(for: pair)
        await transport.setStatus(503)
        let fallback = try await store.lookup(for: pair, forceRefresh: true)
        XCTAssertEqual(fallback.quote, first)
        XCTAssertTrue(fallback.usedOfflineCache)
        XCTAssertTrue(fallback.failureDescription?.contains("503") == true)
        let repeated = try await store.lookup(for: pair)
        XCTAssertTrue(repeated.usedOfflineCache)
        XCTAssertFalse(repeated.failureDescription?.contains("No saved") == true)
    }

    func testLegacyProviderKeysAndPegRowsDecode() async throws {
        for (providers, expected) in [("[\"ECB\",\"TCMB\"]", ["ECB", "TCMB"]), (nil, [])] {
            let providerField = providers.map { ",\"providers\":\($0)" } ?? ""
            let data = Data("[{\"date\":\"2026-09-29\",\"base\":\"USD\",\"quote\":\"TRY\",\"rate\":40.12\(providerField)}]".utf8)
            let transport = MockRateTransport(data: data)
            let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
            let result = try await store.quote(for: pair)
            XCTAssertEqual(result.providers, expected)
        }
    }

    func testInvalidCurrencyDoesNotStartNetworkRequest() async throws {
        let transport = MockRateTransport(data: Self.response())
        let store = ExchangeRateStore(cacheURL: nil, loader: { try await transport.load($0) })
        do {
            _ = try await store.lookup(for: CurrencyPair(base: "US/D", quote: "TRY"))
            XCTFail("Malformed currency code must be rejected")
        } catch {
            XCTAssertEqual(error as? ExchangeRateError, .invalidCurrency)
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    private static func response(base: String = "USD", quote: String = "TRY",
                                 rate: String = "40.12", date: String = "2026-09-29") -> Data {
        Data("""
        [{"date":"\(date)","base":"\(base)","quote":"\(quote)","rate":\(rate),"providers":[
        {"key":"TCMB","date":"2026-09-29","rate":40.13},
        {"key":"ECB","date":"2026-09-29","rate":40.11},
        {"key":"OUTLIER","date":"2026-09-29","rate":9,"excluded":true}]}]
        """.utf8)
    }
}

private actor MockRateTransport {
    let data: Data
    var offline: Bool
    var status = 200
    let delayNanoseconds: UInt64
    var requests: [URLRequest] = []

    init(data: Data, offline: Bool = false, delayNanoseconds: UInt64 = 0) {
        self.data = data
        self.offline = offline
        self.delayNanoseconds = delayNanoseconds
    }

    func setOffline(_ value: Bool) { offline = value }
    func setStatus(_ value: Int) { status = value }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if offline { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}

private final class RateTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ date: Date) { stored = date }
    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        stored.addTimeInterval(seconds)
    }
}
