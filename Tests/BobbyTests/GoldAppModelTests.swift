import AppKit
import BobbyCore
import XCTest
@testable import Bobby

@MainActor
final class GoldAppModelTests: XCTestCase {
    private enum WaitError: Error { case timedOut }

    private actor Transport {
        private(set) var goldRequests: [URLRequest] = []
        private(set) var rateRequests: [URLRequest] = []
        private var goldOffline = false

        func setGoldOffline(_ offline: Bool) { goldOffline = offline }

        func loadGold(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            goldRequests.append(request)
            try await Task.sleep(nanoseconds: 30_000_000)
            if goldOffline { throw URLError(.notConnectedToInternet) }
            let data = Data("""
            [
              {"Kod":"PC","Alis":"10.516,94","Satis":"11.140,00","GuncellenmeZamani":"03.10.2026 12:00:00","Aciklama":"Çeyrek"},
              {"Kod":"PY","Alis":"21.034,88","Satis":"22.280,00","GuncellenmeZamani":"03.10.2026 12:00:00","Aciklama":"Yarım"}
            ]
            """.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        func loadRate(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            rateRequests.append(request)
            try await Task.sleep(nanoseconds: 10_000_000)
            let data = Data("""
            [{"date":"2026-10-03","base":"TRY","quote":"USD","rate":0.02,"providers":["TCMB"]}]
            """.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @MainActor
    private struct Fixture {
        let model: AppModel
        let transport: Transport
        let goldStore: GoldPriceStore
        let directory: URL

        func cleanUp() {
            model.flushSave()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture(refreshInterval: TimeInterval = 60) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bobby-gold-model-\(UUID().uuidString)")
        let scratch = Scratch(text: "")
        try ScratchStore(fileURL: directory.appendingPathComponent("scratches.json"))
            .save(ScratchCollection(scratches: [scratch], selectedID: scratch.id))
        let transport = Transport()
        let instant = ISO8601DateFormatter().date(from: "2026-10-03T09:05:00Z")!
        let rates = ExchangeRateStore(cacheURL: nil, loader: { try await transport.loadRate($0) }, now: { instant })
        let gold = GoldPriceStore(cacheURL: nil, refreshInterval: refreshInterval,
                                  loader: { try await transport.loadGold($0) }, now: { instant })
        let model = AppModel(directory: directory, rates: rates, goldPrices: gold)
        return Fixture(model: model, transport: transport, goldStore: gold, directory: directory)
    }

    func testRenderingPreviewDoesNotFetchGoldOrChangeSavedScratch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let collection = fixture.model.collection
        let preview = fixture.model.previewResults(for: "quarter gold\n5 + 5", yearBasis: 365)
        XCTAssertEqual(preview.first?.text, "Getting gold price…")
        XCTAssertTrue(preview.contains { $0.lineIndex == 1 && $0.text == "10" })
        await Task.yield()
        let goldCount = await fixture.transport.goldRequests.count
        let rateCount = await fixture.transport.rateRequests.count
        XCTAssertEqual(goldCount, 0)
        XCTAssertEqual(rateCount, 0)
        XCTAssertEqual(fixture.model.collection, collection)
        XCTAssertEqual(fixture.model.currentText, "")
        XCTAssertTrue(fixture.model.results.isEmpty)
    }

    func testLiveGoldRequestReplacesLoadingWithDatedDualPrice() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.updateText("çeyrek altın")
        XCTAssertEqual(fixture.model.results.first?.text, "Getting gold price…")
        try await waitFor { fixture.model.results.first?.copyText != nil }
        let result = try XCTUnwrap(fixture.model.results.first)
        XCTAssertEqual(result.text, "Dealer buy 10,516.94 · Dealer sell 11,140 TL")
        XCTAssertTrue(result.usesCompactValue)
        XCTAssertTrue(result.detail.contains("Altınkaynak"))
        XCTAssertTrue(result.detail.contains("2026-10-03 12:00"))
        XCTAssertTrue(result.copyText?.contains("Dealer buy (you receive): 10,516.94 TL") == true)
        XCTAssertTrue(result.copyText?.contains("Dealer sell (you pay): 11,140 TL") == true)
        XCTAssertTrue(result.copyText?.contains(GoldPriceStore.sourceURL.absoluteString) == true)
        XCTAssertEqual(fixture.model.currentText, "çeyrek altın")
        let goldRequests = await fixture.transport.goldRequests
        let rateCount = await fixture.transport.rateRequests.count
        XCTAssertEqual(goldRequests.count, 1)
        XCTAssertEqual(goldRequests.first?.url, GoldPriceStore.sourceURL)
        XCTAssertNil(goldRequests.first?.httpBody)
        XCTAssertEqual(rateCount, 0)
    }

    func testGoldVariableRecalculatesArithmeticAndDependentCurrencyConversion() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.updateText("q = 2 çeyrek altın sell\nq * .75\nq TRY to USD")
        XCTAssertEqual(fixture.model.results.first?.text, "Getting gold price…")
        XCTAssertFalse(fixture.model.results.contains { $0.isError })
        try await waitFor { fixture.model.results.contains { $0.lineIndex == 2 && $0.copyText == "445.6 USD" } }
        XCTAssertTrue(fixture.model.results.contains { $0.lineIndex == 0 && $0.copyText == "22,280 TL" })
        XCTAssertTrue(fixture.model.results.contains { $0.lineIndex == 1 && $0.text == "16,710 TL" })
        XCTAssertFalse(fixture.model.results.contains { $0.isError })
        fixture.model.updateText("q = 5 çeyrek altın sell\nq * .75\nq TRY to USD")
        XCTAssertTrue(fixture.model.results.contains { $0.lineIndex == 0 && $0.copyText == "55,700 TL" })
        XCTAssertTrue(fixture.model.results.contains { $0.lineIndex == 1 && $0.text == "41,775 TL" })
        XCTAssertTrue(fixture.model.results.contains { $0.lineIndex == 2 && $0.copyText == "1,114 USD" })
        let goldCount = await fixture.transport.goldRequests.count
        let rateRequests = await fixture.transport.rateRequests
        XCTAssertEqual(goldCount, 1, "Changing quantity reuses the dated unit quote")
        XCTAssertEqual(rateRequests.count, 1)
        XCTAssertTrue(rateRequests.first?.url?.absoluteString.contains("base=TRY") == true)
        XCTAssertNil(rateRequests.first?.httpBody)
    }

    func testGoldFailureShowsUnavailableUntilExplicitRefreshSucceeds() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        await fixture.transport.setGoldOffline(true)
        fixture.model.updateText("quarter gold")
        try await waitFor { fixture.model.results.first?.isError == true }
        let failed = try XCTUnwrap(fixture.model.results.first)
        XCTAssertEqual(failed.text, "Gold price unavailable")
        XCTAssertNil(failed.copyText)
        XCTAssertTrue(failed.tooltip.contains("No saved"))
        fixture.model.updateText("2 quarter gold")
        await Task.yield()
        var goldCount = await fixture.transport.goldRequests.count
        XCTAssertEqual(goldCount, 1, "Editing an unavailable product does not flood the service")
        await fixture.transport.setGoldOffline(false)
        fixture.model.refreshRates(force: true)
        try await waitFor { fixture.model.results.first?.copyText != nil }
        XCTAssertFalse(fixture.model.results.first?.isError == true)
        XCTAssertTrue(fixture.model.results.first?.text.contains("Dealer sell 22,280 TL") == true)
        goldCount = await fixture.transport.goldRequests.count
        XCTAssertEqual(goldCount, 2)
    }

    func testOfflineGoldFallbackKeepsPricesAndSavedProvenanceVisible() async throws {
        let fixture = try makeFixture(refreshInterval: 0)
        defer { fixture.cleanUp() }
        _ = try await fixture.goldStore.lookup(for: .quarterCoin)
        await fixture.transport.setGoldOffline(true)
        fixture.model.updateText("quarter gold")
        try await waitFor { fixture.model.results.first?.copyText != nil }
        let result = try XCTUnwrap(fixture.model.results.first)
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("Dealer buy 10,516.94"))
        XCTAssertTrue(result.text.contains("Dealer sell 11,140 TL"))
        XCTAssertTrue(result.detail.contains("saved"))
        XCTAssertTrue(result.detail.contains("Altınkaynak"))
        XCTAssertTrue(result.tooltip.contains("Using a saved quote"))
        XCTAssertTrue(result.copyText?.contains("offline cache") == true)
        let goldCount = await fixture.transport.goldRequests.count
        XCTAssertEqual(goldCount, 2)
    }

    func testPreparingPracticeGoldRatesSharesBoardAndPreservesCurrentScratch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let collection = fixture.model.collection
        let text = "quarter gold\nhalf gold"
        fixture.model.preparePreviewRates(for: text, yearBasis: 365)
        try await waitFor {
            fixture.model.previewResults(for: text, yearBasis: 365).allSatisfy { $0.copyText != nil }
        }
        let preview = fixture.model.previewResults(for: text, yearBasis: 365)
        XCTAssertEqual(preview.count, 2)
        XCTAssertTrue(preview.allSatisfy { $0.usesCompactValue && !$0.isError })
        XCTAssertEqual(fixture.model.collection, collection)
        XCTAssertTrue(fixture.model.results.isEmpty)
        let goldCount = await fixture.transport.goldRequests.count
        XCTAssertEqual(goldCount, 1, "Two product previews share one public price board")
    }

    func testGoldQuoteArrivalCannotReplaceNewlySelectedScratchText() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let originalID = try XCTUnwrap(fixture.model.collection.selectedID)
        fixture.model.updateText("quarter gold")
        fixture.model.newScratch()
        let newID = fixture.model.collection.selectedID
        try await waitFor { fixture.model.previewResults(for: "quarter gold", yearBasis: 365).first?.copyText != nil }
        XCTAssertEqual(fixture.model.collection.selectedID, newID)
        XCTAssertEqual(fixture.model.currentText, "")
        XCTAssertTrue(fixture.model.results.isEmpty)
        XCTAssertEqual(fixture.model.collection.scratches.first { $0.id == originalID }?.text, "quarter gold")
        fixture.model.select(originalID)
        XCTAssertTrue(fixture.model.results.first?.copyText != nil)
        let goldCount = await fixture.transport.goldRequests.count
        XCTAssertEqual(goldCount, 1)
    }

    private func waitFor(_ condition: @MainActor () -> Bool,
                         file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the deterministic price request", file: file, line: line)
        throw WaitError.timedOut
    }
}
