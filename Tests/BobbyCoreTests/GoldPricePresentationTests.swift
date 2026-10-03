import Foundation
import XCTest
@testable import BobbyCore

final class GoldPricePresentationTests: XCTestCase {
    private let observed = ISO8601DateFormatter().date(from: "2026-10-03T18:32:37Z")!

    func testBothSidesAreLabeledWithVisibleSourceAndIstanbulTime() throws {
        let result = try make()
        XCTAssertEqual(result.valueText, "Dealer buy 10,516.94 · Dealer sell 11,140 TL")
        XCTAssertEqual(result.detail, "Altınkaynak · 2026-10-03 21:32")
        XCTAssertTrue(result.showsBothSides)
        XCTAssertTrue(result.tooltip.contains("Dealer buy (you receive): 10,516.94 TL"))
        XCTAssertTrue(result.tooltip.contains("Dealer sell (you pay): 11,140 TL"))
        XCTAssertTrue(result.tooltip.contains("Çeyrek (PC)"))
        XCTAssertTrue(result.tooltip.contains("2026-10-03 21:32:37 Europe/Istanbul"))
        XCTAssertTrue(result.tooltip.contains(GoldPriceStore.sourceURL.absoluteString))
        XCTAssertTrue(result.tooltip.contains("No mint year is inferred."))
    }

    func testQuantityMultipliesTheRetailQuoteWithoutIntermediateRounding() throws {
        let quote = quote(buy: decimal("1.2345"), sell: decimal("1.9876"))
        let result = try make(quantity: 3, quote: quote)
        XCTAssertEqual(result.valueText, "Dealer buy 3.7 · Dealer sell 5.96 TL")
        XCTAssertTrue(result.tooltip.contains("Quarter gold: 3 coins"))
        XCTAssertEqual(quote.dealerBuy, decimal("1.2345"))
    }

    func testBothPriceCopyPreservesMeaningSourceTimeAndQuantity() throws {
        let result = try make(quantity: 2)
        XCTAssertTrue(result.copyText.hasPrefix("Quarter gold: 2 coins\n"))
        XCTAssertTrue(result.copyText.contains("Dealer buy (you receive): 21,033.88 TL"))
        XCTAssertTrue(result.copyText.contains("Dealer sell (you pay): 22,280 TL"))
        XCTAssertTrue(result.copyText.contains("Altınkaynak · 2026-10-03 21:32 Europe/Istanbul"))
        XCTAssertTrue(result.copyText.contains(GoldPriceStore.sourceURL.absoluteString))
    }

    func testExplicitSidesCopyScalarMoneyAndLabelOtherSideAsUnitQuote() throws {
        let buy = try make(quantity: 2, side: .dealerBuy)
        XCTAssertEqual(buy.valueText, "Dealer buy: 21,033.88 TL")
        XCTAssertEqual(buy.copyText, "21,033.88 TL")
        XCTAssertFalse(buy.showsBothSides)
        XCTAssertTrue(buy.tooltip.contains("Dealer sell (you pay): 11,140 TL per coin"))
        let sell = try make(quantity: 2, side: .dealerSell)
        XCTAssertEqual(sell.valueText, "Dealer sell: 22,280 TL")
        XCTAssertEqual(sell.copyText, "22,280 TL")
        XCTAssertTrue(sell.tooltip.contains("Dealer buy (you receive): 10,516.94 TL per coin"))
    }

    func testSavedQuoteIsVisibleWithoutLosingDateAndOtherStatusesStayInDetails() throws {
        let result = try make(offline: true, refreshing: true, now: observed.addingTimeInterval(3600))
        XCTAssertEqual(result.detail, "Altınkaynak · 2026-10-03 21:32 · saved")
        XCTAssertFalse(result.detail.contains("\n"))
        XCTAssertTrue(result.tooltip.contains("Using a saved quote after refreshing failed."))
        XCTAssertTrue(result.tooltip.contains("Test network failure"))
        XCTAssertTrue(result.tooltip.contains("over 15 minutes old"))
        XCTAssertTrue(result.tooltip.contains("Refreshing the dealer's price board."))
        XCTAssertTrue(result.copyText.contains("offline cache · older quote · refreshing"))
    }

    func testOldObservationIsMarkedEvenWhenFetchSucceededRecently() throws {
        let quote = quote(fetched: observed.addingTimeInterval(3600))
        let result = try make(quote: quote, now: observed.addingTimeInterval(3600))
        XCTAssertEqual(result.detail, "Altınkaynak · 2026-10-03 21:32 · older")
        XCTAssertFalse(result.tooltip.contains("refreshing failed"))
        XCTAssertTrue(result.tooltip.contains("Retrieved: 2026-10-03 22:32:37"))
    }

    func testFreshRefreshShowsStatusAndRetainsAnswer() throws {
        let result = try make(refreshing: true)
        XCTAssertEqual(result.valueText, "Dealer buy 10,516.94 · Dealer sell 11,140 TL")
        XCTAssertEqual(result.detail, "Altınkaynak · 2026-10-03 21:32 · updating")
    }

    func testGramListingAndZeroQuantityRemainExplicit() throws {
        let gram = quote(product: .gram, buy: decimal("6537.50"), sell: 6670)
        let result = try make(product: .gram, quantity: decimal("0.5"), quote: gram)
        XCTAssertEqual(result.valueText, "Dealer buy 3,268.75 · Dealer sell 3,335 TL")
        XCTAssertTrue(result.tooltip.contains("Gram Altın (PGA)"))
        XCTAssertTrue(result.tooltip.contains("not its other gram or bullion listings"))
        XCTAssertEqual(try make(quantity: 0).valueText, "Dealer buy 0 · Dealer sell 0 TL")
    }

    func testMismatchedQuoteAndInvalidPricesCannotBeDisplayed() {
        XCTAssertThrowsError(try make(quote: quote(product: .gram))) {
            XCTAssertEqual($0 as? GoldPricePresentationError, .mismatchedProduct)
        }
        for (buy, sell): (Decimal, Decimal) in [(0, 10), (-1, 10), (.nan, 10), (10, .nan), (11, 10)] {
            XCTAssertThrowsError(try make(quote: quote(buy: buy, sell: sell))) {
                XCTAssertEqual($0 as? GoldPricePresentationError, .invalidQuote)
            }
        }
    }

    func testInvalidQuantityAndOverflowOrUnderflowHaveNoCopyableAnswer() {
        for quantity: Decimal in [-1, .nan] {
            XCTAssertThrowsError(try make(quantity: quantity)) {
                XCTAssertEqual($0 as? GoldPricePresentationError, .invalidQuantity)
            }
        }
        for (quantity, price) in [(decimal("1e127"), decimal("1e40")), (decimal("1e-127"), decimal("1e-10"))] {
            XCTAssertThrowsError(try make(quantity: quantity, quote: quote(buy: price, sell: price))) {
                XCTAssertEqual($0 as? GoldPricePresentationError, .amountOutOfRange)
            }
        }
    }

    func testUnselectedSideOverflowDoesNotBreakValidScalarOrDependencies() throws {
        let quote = quote(buy: decimal("1e65"), sell: decimal("1e66"))
        let request = GoldRequest(product: .quarterCoin, quantity: decimal("1e100"), side: .dealerBuy)
        let result = try GoldPricePresentation.make(request: request, lookup: GoldLookup(quote: quote, usedOfflineCache: false), now: observed)
        XCTAssertTrue(result.valueText.hasPrefix("Dealer buy:"))
        XCTAssertTrue(result.copyText.hasSuffix(" TL"))
        XCTAssertThrowsError(try make(quantity: request.quantity, quote: quote))
        let evaluated = CalculationEngine().evaluate("price = 10^100 ceyrek altin buy\nprice * .1", goldQuotes: [.quarterCoin: quote])
        XCTAssertEqual(evaluated.first?.value, decimal("1" + String(repeating: "0", count: 165)))
        XCTAssertEqual(evaluated.last?.value, decimal("1" + String(repeating: "0", count: 164)))
    }

    private func make(product: GoldProduct = .quarterCoin, quantity: Decimal = 1, side: GoldSide? = nil,
                      quote: GoldQuote? = nil, offline: Bool = false, refreshing: Bool = false, now: Date? = nil) throws -> GoldPricePresentation {
        try GoldPricePresentation.make(request: GoldRequest(product: product, quantity: quantity, side: side),
                                       lookup: GoldLookup(quote: quote ?? self.quote(), usedOfflineCache: offline,
                                                          failureDescription: offline ? "Test network failure" : nil),
                                       isRefreshing: refreshing, now: now ?? observed)
    }

    private func quote(product: GoldProduct = .quarterCoin, buy: Decimal? = nil, sell: Decimal = 11_140,
                       fetched: Date? = nil) -> GoldQuote {
        GoldQuote(product: product, dealerBuy: buy ?? decimal("10516.94"), dealerSell: sell,
                  observedAt: observed, fetchedAt: fetched ?? observed, productLabel: product.providerName)
    }

    private func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
}
