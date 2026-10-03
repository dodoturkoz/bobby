import Foundation
import XCTest
@testable import BobbyCore

final class GoldPricesTests: XCTestCase {
    private let instant = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!

    func testPublicBoardKeepsDealerSidesExactNumbersLabelAndIstanbulDate() async throws {
        let transport = MockGoldTransport(data: Self.board([
            Self.row(label: " Çeyrek ", buy: "10.516,941234567890123456789", sell: "11.140,00")
        ]))
        let store = makeStore(transport)
        let result = try await store.lookup(for: .quarterCoin)

        XCTAssertEqual(result.quote.product, .quarterCoin)
        XCTAssertEqual(result.quote.dealerBuy, Decimal(string: "10516.941234567890123456789"))
        XCTAssertEqual(result.quote.dealerSell, Decimal(11140))
        XCTAssertEqual(result.quote.productLabel, " Çeyrek ")
        XCTAssertEqual(result.quote.observedAt, instant)
        XCTAssertEqual(result.quote.fetchedAt, instant)
        XCTAssertEqual(result.quote.sourceName, "Altınkaynak")
        XCTAssertEqual(result.quote.sourceURL, GoldPriceStore.sourceURL)
        XCTAssertFalse(result.usedOfflineCache)
        XCTAssertNil(result.failureDescription)

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://static.altinkaynak.com/public/Gold")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testWholeBoardIsCachedAndGramUsesPGAWithoutMergingGA() async throws {
        let products: [GoldProduct] = [.quarterCoin, .oldQuarterCoin, .halfCoin, .oldHalfCoin,
                                      .fullCoin, .oldFullCoin, .ataCoin, .gram]
        let transport = MockGoldTransport(data: Self.board(products.map {
            Self.row(code: $0.rawValue, label: $0.providerName)
        } + [Self.row(code: "GA", label: "Gram Altın ", sell: "10.999,00")]))
        let store = makeStore(transport)
        for product in products {
            let result = try await store.lookup(for: product)
            XCTAssertEqual(result.quote.product, product)
            XCTAssertEqual(result.quote.dealerSell, 11140)
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testFreshCacheUsesSixtySecondsAndForceRefreshBypassesIt() async throws {
        let clock = GoldTestClock(instant)
        let transport = MockGoldTransport(data: Self.board([Self.row()]))
        let store = GoldPriceStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { clock.value })
        _ = try await store.lookup(for: .quarterCoin)
        clock.advance(59)
        for _ in 0..<5 { _ = try await store.lookup(for: .quarterCoin) }
        var count = await transport.requests.count
        XCTAssertEqual(count, 1)
        clock.advance(1)
        _ = try await store.lookup(for: .quarterCoin)
        count = await transport.requests.count
        XCTAssertEqual(count, 2)
        _ = try await store.lookup(for: .quarterCoin, forceRefresh: true)
        count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testOfflineFallbackPreservesObservationAndRetriesOnceAfterCooldown() async throws {
        let clock = GoldTestClock(instant)
        let transport = MockGoldTransport(data: Self.board([Self.row(), Self.row(code: "EC")]))
        let store = GoldPriceStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { clock.value })
        let original = try await store.quote(for: .quarterCoin)
        clock.advance(61)
        await transport.setOffline(true)
        let fallback = try await store.lookup(for: .quarterCoin)
        XCTAssertEqual(fallback.quote, original)
        XCTAssertTrue(fallback.usedOfflineCache)
        XCTAssertTrue(fallback.failureDescription?.contains("internet") == true)
        _ = try await store.lookup(for: .quarterCoin)
        let oldQuarter = try await store.lookup(for: .oldQuarterCoin)
        XCTAssertTrue(oldQuarter.usedOfflineCache)
        var count = await transport.requests.count
        XCTAssertEqual(count, 2)

        clock.advance(60)
        await transport.setOffline(false)
        let restored = try await store.lookup(for: .quarterCoin)
        XCTAssertFalse(restored.usedOfflineCache)
        XCTAssertEqual(restored.quote.fetchedAt, clock.value)
        count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testNoSavedQuoteThrowsAndOfflineCooldownCoversOtherProducts() async throws {
        let transport = MockGoldTransport(data: Data(), offline: true)
        let store = makeStore(transport)
        let products: [GoldProduct] = [.quarterCoin, .gram, .halfCoin, .quarterCoin]
        for product in products {
            do {
                _ = try await store.lookup(for: product)
                XCTFail("An unavailable quote must not fabricate a price")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("No saved"))
                XCTAssertTrue(error.localizedDescription.contains("internet"))
            }
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        let cached = await store.cachedQuote(for: .quarterCoin)
        XCTAssertNil(cached)
        await transport.setOffline(false)
        await transport.setData(Self.board([Self.row()]))
        let recovered = try await store.lookup(for: .quarterCoin, forceRefresh: true)
        XCTAssertFalse(recovered.usedOfflineCache)
    }

    func testConcurrentProductsShareOnePendingBoardFetch() async throws {
        let transport = MockGoldTransport(data: Self.board([Self.row(), Self.row(code: "EC")]), gated: true)
        let store = makeStore(transport)
        let lookups = Task {
            try await withThrowingTaskGroup(of: GoldLookup.self) { group in
                for index in 0..<20 {
                    group.addTask { try await store.lookup(for: index.isMultiple(of: 2) ? .quarterCoin : .oldQuarterCoin) }
                }
                var results: [GoldLookup] = []
                for try await result in group { results.append(result) }
                return results
            }
        }
        await transport.waitForRequest()
        await transport.release()
        let results = try await lookups.value
        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { !$0.usedOfflineCache && $0.quote.dealerSell == 11140 })
        XCTAssertEqual(Set(results.map(\.quote.product)), [.quarterCoin, .oldQuarterCoin])
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testPartialBoardKeepsOtherProductsAndSavedFallbackForMissingProduct() async throws {
        let transport = MockGoldTransport(data: Self.board([Self.row(), Self.row(code: "EC")]))
        let store = makeStore(transport)
        let original = try await store.quote(for: .quarterCoin)
        await transport.setData(Self.board([Self.row(code: "EC", sell: "12.000,00"),
                                           Self.row(code: "PY", buy: "broken")]))
        let fallback = try await store.lookup(for: .quarterCoin, forceRefresh: true)
        XCTAssertEqual(fallback.quote, original)
        XCTAssertTrue(fallback.usedOfflineCache)
        XCTAssertTrue(fallback.failureDescription?.contains("did not include") == true)
        let retained = try await store.lookup(for: .oldQuarterCoin)
        XCTAssertEqual(retained.quote.dealerSell, 12000)
        XCTAssertFalse(retained.usedOfflineCache)
        do {
            _ = try await store.lookup(for: .halfCoin)
            XCTFail("Malformed product should not have a quote")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("invalid"))
        }
        _ = try await store.lookup(for: .quarterCoin)
        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
        let saved = await store.cachedQuote(for: .quarterCoin)
        XCTAssertEqual(saved, original)
    }

    func testDuplicateProductIsRejectedEvenWhenOneCopyIsMalformed() async throws {
        for duplicate in [Self.row(), Self.row(buy: "invalid")] {
            let transport = MockGoldTransport(data: Self.board([Self.row(), duplicate, Self.row(code: "EC")]))
            let store = makeStore(transport)
            do {
                _ = try await store.lookup(for: .quarterCoin)
                XCTFail("Duplicate product codes must not select an arbitrary quote")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid"))
            }
            let oldQuote = try await store.lookup(for: .oldQuarterCoin)
            XCTAssertEqual(oldQuote.quote.dealerBuy, Decimal(string: "10516.94"))
            let missing = await store.cachedQuote(for: .quarterCoin)
            XCTAssertNil(missing)
        }
    }

    func testStrictTurkishFeedPricesRejectEnglishAmbiguityAndInvalidValues() async throws {
        let invalidPrices = ["1,234.56", "10516.94", "10.51,00", "1.23.456,00", "NaN", "-1,00",
                             "0,00", "+1,00", "1e4", " 10.516,94", "10.516,94\n", "10.516,9x",
                             "0,00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
                             "10.516,94123456789012345678901234567890123456789"]
        for price in invalidPrices {
            let transport = MockGoldTransport(data: Self.board([Self.row(buy: price)]))
            let store = makeStore(transport)
            do {
                _ = try await store.lookup(for: .quarterCoin)
                XCTFail("Invalid Turkish feed number was accepted: \(price)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid"))
            }
        }
        for buy in ["10516,94", "10.516,9400", "10516", "10.516"] {
            let transport = MockGoldTransport(data: Self.board([Self.row(buy: buy)]))
            let store = makeStore(transport)
            _ = try await store.lookup(for: .quarterCoin)
        }
    }

    func testInvalidSpreadMissingFieldsAndWrongFieldTypesDoNotBecomeQuotes() async throws {
        var missing = Self.row()
        missing.removeValue(forKey: "Satis")
        var numeric = Self.row()
        numeric["Alis"] = 10516.94
        let invalidRows = [Self.row(buy: "12.000,00"), Self.row(sell: "0,00"),
                           Self.row(label: " \n "), missing, numeric]
        for row in invalidRows {
            let store = makeStore(MockGoldTransport(data: Self.board([row])))
            do {
                _ = try await store.lookup(for: .quarterCoin)
                XCTFail("Invalid product should not produce a quote")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid"))
            }
        }
    }

    func testStrictDatesRejectInvalidCalendarDatesAndUnreasonableFutureQuotes() async throws {
        let invalidDates = ["31.09.2026 15:00:00", "29.02.2026 15:00:00", "03.10.2026 24:00:00",
                            "03.10.2026 15:60:00", "03.10.2026 15:00:60", "3.10.2026 15:00:00",
                            "2026-10-03T12:00:00Z", "03.10.2026 15:00:00 ", "03.10.2026 15:05:01"]
        for timestamp in invalidDates {
            let store = makeStore(MockGoldTransport(data: Self.board([Self.row(timestamp: timestamp)])))
            do {
                _ = try await store.lookup(for: .quarterCoin)
                XCTFail("Invalid date was accepted: \(timestamp)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid"))
            }
        }
        for timestamp in ["29.02.2024 15:00:00", "03.10.2026 15:05:00"] {
            let store = makeStore(MockGoldTransport(data: Self.board([Self.row(timestamp: timestamp)])))
            let lookup = try await store.lookup(for: .quarterCoin)
            XCTAssertFalse(lookup.usedOfflineCache)
        }
    }

    func testUnsupportedMalformedRowsDoNotBlockSupportedProduct() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            Self.row(), ["Kod": "UNKNOWN", "Alis": NSNull()], ["Kod": 123], "unsupported row", NSNull()
        ])
        let store = makeStore(MockGoldTransport(data: data))
        let quote = try await store.quote(for: .quarterCoin)
        XCTAssertEqual(quote.dealerSell, 11140)
    }

    func testInvalidRootAndHTTPFailureCanOnlyUseExplicitSavedFallback() async throws {
        let transport = MockGoldTransport(data: Self.board([Self.row()]))
        let store = makeStore(transport)
        let original = try await store.quote(for: .quarterCoin)
        for payload in [Data("broken json".utf8), Data("{}".utf8), Data("null".utf8)] {
            await transport.setData(payload)
            let fallback = try await store.lookup(for: .quarterCoin, forceRefresh: true)
            XCTAssertEqual(fallback.quote, original)
            XCTAssertTrue(fallback.usedOfflineCache)
            XCTAssertTrue(fallback.failureDescription?.contains("invalid price board") == true)
        }
        await transport.setStatus(503)
        let fallback = try await store.lookup(for: .quarterCoin, forceRefresh: true)
        XCTAssertTrue(fallback.usedOfflineCache)
        XCTAssertTrue(fallback.failureDescription?.contains("503") == true)
        let repeated = try await store.lookup(for: .quarterCoin)
        XCTAssertTrue(repeated.usedOfflineCache)
    }

    func testDiskCacheRoundTripPreservesPrecisePricesAndMetadataOffline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gold-prices.json")
        let transport = MockGoldTransport(data: Self.board([
            Self.row(label: "Çeyrek", buy: "10.516,941234567890123456789", sell: "11.140,01234567890123456789")
        ]))
        let first = GoldPriceStore(cacheURL: url, loader: { try await transport.load($0) }, now: { self.instant })
        let fetched = try await first.quote(for: .quarterCoin)
        let storedData = try Data(contentsOf: url)
        let cache = try XCTUnwrap(JSONSerialization.jsonObject(with: storedData) as? [String: Any])
        XCTAssertEqual(cache["version"] as? Int, 1)
        let rows = try XCTUnwrap(cache["quotes"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["dealerBuy"] as? String, "10516.941234567890123456789")
        XCTAssertEqual(rows.first?["dealerSell"] as? String, "11140.01234567890123456789")

        let offline = MockGoldTransport(data: Data(), offline: true)
        let restart = GoldPriceStore(cacheURL: url, loader: { try await offline.load($0) },
                                     now: { self.instant.addingTimeInterval(3600) })
        let cached = await restart.cachedQuote(for: .quarterCoin)
        XCTAssertEqual(cached, fetched)
        let result = try await restart.lookup(for: .quarterCoin)
        XCTAssertEqual(result.quote, fetched)
        XCTAssertTrue(result.usedOfflineCache)
        XCTAssertNotNil(result.failureDescription)
        XCTAssertEqual(try Data(contentsOf: url), storedData)
    }

    func testCorruptUnsupportedAndInvalidCacheIsIgnoredWithoutChangingFile() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gold-prices.json")
        let valid = GoldQuote(product: .quarterCoin, dealerBuy: 100, dealerSell: 101,
                              observedAt: instant, fetchedAt: instant, productLabel: "Çeyrek")
        let encoded = try JSONEncoder().encode(valid)
        let validRow = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var unknown = validRow
        unknown["product"] = "UNKNOWN"
        var invalidSpread = validRow
        invalidSpread["dealerBuy"] = "102"
        var invalidDecimal = validRow
        invalidDecimal["dealerBuy"] = "100garbage"
        var invalidFuture = validRow
        invalidFuture["observedAt"] = instant.addingTimeInterval(301).timeIntervalSinceReferenceDate
        let invalidData = [Data("broken json".utf8), Data("{\"version\":2,\"quotes\":[]}".utf8)]
            + (try [unknown, invalidSpread, invalidDecimal, invalidFuture].map {
                try JSONSerialization.data(withJSONObject: ["version": 1, "quotes": [$0]])
            })
            + [try JSONSerialization.data(withJSONObject: ["version": 1, "quotes": [validRow, validRow]])]
        for data in invalidData {
            try data.write(to: url)
            let store = GoldPriceStore(cacheURL: url, loader: { _ in throw URLError(.notConnectedToInternet) },
                                       now: { self.instant })
            let cached = await store.cachedQuote(for: .quarterCoin)
            let readError = await store.cacheReadError
            XCTAssertNil(cached)
            XCTAssertNotNil(readError)
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testCacheWriteFailureDoesNotTurnAValidQuoteIntoLookupFailure() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file-not-directory")
        try Data("preserve".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("gold-prices.json")
        let transport = MockGoldTransport(data: Self.board([Self.row()]))
        let store = GoldPriceStore(cacheURL: url, loader: { try await transport.load($0) }, now: { self.instant })
        let result = try await store.lookup(for: .quarterCoin)
        XCTAssertFalse(result.usedOfflineCache)
        XCTAssertNil(result.failureDescription)
        let writeError = await store.cacheWriteError
        XCTAssertNotNil(writeError)
        let cached = await store.cachedQuote(for: .quarterCoin)
        XCTAssertEqual(cached, result.quote)
        XCTAssertEqual(try Data(contentsOf: blocker), Data("preserve".utf8))
    }

    private func makeStore(_ transport: MockGoldTransport) -> GoldPriceStore {
        GoldPriceStore(cacheURL: nil, loader: { try await transport.load($0) }, now: { self.instant })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bobby-gold-tests-" + UUID().uuidString)
    }

    private static func row(code: String = "PC", label: String = "Çeyrek", buy: String = "10.516,94",
                            sell: String = "11.140,00", timestamp: String = "03.10.2026 15:00:00") -> [String: Any] {
        ["Kod": code, "Aciklama": label, "Alis": buy, "Satis": sell, "GuncellenmeZamani": timestamp]
    }

    private static func board(_ rows: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: rows)
    }
}

private actor MockGoldTransport {
    var data: Data
    var offline: Bool
    var status = 200
    var requests: [URLRequest] = []
    var gated: Bool
    private var blockers: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    init(data: Data, offline: Bool = false, gated: Bool = false) {
        self.data = data
        self.offline = offline
        self.gated = gated
    }

    func setData(_ value: Data) { data = value }
    func setOffline(_ value: Bool) { offline = value }
    func setStatus(_ value: Int) { status = value }

    func waitForRequest() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release() {
        gated = false
        let waiting = blockers
        blockers.removeAll()
        for blocker in waiting { blocker.resume() }
    }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let waiting = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiting { waiter.resume() }
        if gated { await withCheckedContinuation { blockers.append($0) } }
        if offline { throw URLError(.notConnectedToInternet) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private final class GoldTestClock: @unchecked Sendable {
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
