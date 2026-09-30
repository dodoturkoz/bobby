import Foundation
import XCTest
@testable import BobbyCore

final class ExchangeRatePresentationTests: XCTestCase {
    private let usdToTL = CurrencyPair(base: "USD", quote: "TRY")
    private let tlToEuro = CurrencyPair(base: "TL", quote: "EUR")

    func testMoneyConversionRoundsOnlyForDisplayAndCopy() throws {
        let request = ConversionRequest(amount: 500, pair: usdToTL)
        let result = try ExchangeRatePresentation.make(request: request, lookup: lookup(rate: decimal("40.123456")))
        XCTAssertEqual(result.valueText, "20,061.73 TL")
        XCTAssertEqual(result.copyText, "20,061.73 TL")
        XCTAssertTrue(result.tooltip.hasPrefix("1 USD = 40.123456 TL\n"))
        XCTAssertEqual(request.amount, 500)
    }

    func testSmallUnitRateKeepsEightDecimalsAndItsDenominator() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 1, pair: tlToEuro, isRateQuery: true),
            lookup: lookup(rate: decimal("0.02123456"), pair: tlToEuro)
        )
        XCTAssertEqual(result.valueText, "1 TL = 0.02123456 EUR")
        XCTAssertEqual(result.copyText, "0.02123456 EUR")
        XCTAssertTrue(result.tooltip.hasPrefix("1 TL = 0.02123456 EUR\n"))
        let copied = CalculationEngine().evaluate(result.copyText).first
        XCTAssertEqual(copied?.value, decimal("0.02123456"))
        XCTAssertEqual(copied?.currency, "EUR")
    }

    func testRateQueriesRoundBeyondEightDecimalsWhileAmountsUseTwo() throws {
        let quote = lookup(rate: decimal("0.021234565"), pair: tlToEuro)
        let rate = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 1, pair: tlToEuro, isRateQuery: true), lookup: quote
        )
        let amount = try ExchangeRatePresentation.make(request: ConversionRequest(amount: 1, pair: tlToEuro), lookup: quote)
        XCTAssertEqual(rate.valueText, "1 TL = 0.02123457 EUR")
        XCTAssertEqual(rate.copyText, "0.02123457 EUR")
        XCTAssertEqual(amount.valueText, "0.02 EUR")
        XCTAssertEqual(amount.copyText, "0.02 EUR")
    }

    func testSourceAndDateAreVisibleWithoutOpeningATooltip() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL),
            lookup: lookup(rate: 40, providers: ["TCMB", "ECB"])
        )
        XCTAssertEqual(result.detail, "Frankfurter · 2026-09-25")
        XCTAssertTrue(result.tooltip.contains("Frankfurter · ECB, TCMB"))
        XCTAssertTrue(result.tooltip.contains("Blended mid-market reference"))
        XCTAssertTrue(result.tooltip.contains("Rate date: 2026-09-25"))
    }

    func testAnOlderObservedDateDoesNotAutomaticallyBecomeAnOfflineWarning() throws {
        let result = try ExchangeRatePresentation.make(request: ConversionRequest(amount: 3, pair: usdToTL), lookup: lookup(rate: 40))
        XCTAssertEqual(result.detail, "Frankfurter · 2026-09-25")
        XCTAssertFalse(result.tooltip.contains("failed"))
        XCTAssertFalse(result.detail.contains("offline"))
    }

    func testAbsentProviderNamesStillShowTheKnownService() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL), lookup: lookup(rate: 40, providers: [])
        )
        XCTAssertEqual(result.detail, "Frankfurter · 2026-09-25")
        XCTAssertTrue(result.tooltip.contains("\nFrankfurter\n"))
    }

    func testOfflineFallbackIsInlineAndExplainsTheFailure() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL),
            lookup: lookup(rate: 40, offline: true, failure: "The rate service could not be reached.")
        )
        XCTAssertEqual(result.valueText, "120 TL")
        XCTAssertEqual(result.detail, "Frankfurter · 2026-09-25 · offline cache")
        XCTAssertTrue(result.tooltip.contains("Using a saved quote after refreshing failed."))
        XCTAssertTrue(result.tooltip.contains("The rate service could not be reached."))
    }

    func testARefreshKeepsTheSavedAnswerAndBothStatusesVisible() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL),
            lookup: lookup(rate: 40, offline: true), isRefreshing: true
        )
        XCTAssertEqual(result.valueText, "120 TL")
        XCTAssertEqual(result.detail, "Frankfurter · 2026-09-25 · offline cache · refreshing")
        XCTAssertTrue(result.tooltip.contains("Refreshing the reference quote."))
    }

    func testIdentityRatesShowTheirOwnSourceAndCanonicalTLNames() throws {
        let pair = CurrencyPair(base: "TL", quote: "try")
        let quote = lookup(rate: 1, pair: pair, providers: [])
        let rate = try ExchangeRatePresentation.make(request: ConversionRequest(amount: 1, pair: pair, isRateQuery: true), lookup: quote)
        let amount = try ExchangeRatePresentation.make(request: ConversionRequest(amount: 50, pair: pair), lookup: quote)
        XCTAssertEqual(rate.valueText, "1 TL = 1 TL")
        XCTAssertEqual(rate.copyText, "1 TL")
        XCTAssertEqual(rate.detail, "Identity rate · 2026-09-25")
        XCTAssertTrue(rate.tooltip.contains("Same currency"))
        XCTAssertFalse(rate.tooltip.contains("Frankfurter"))
        XCTAssertEqual(amount.valueText, "50 TL")
    }

    func testZeroAndNegativeAmountsRemainValidAndDecimalBased() throws {
        let zero = try ExchangeRatePresentation.make(request: ConversionRequest(amount: 0, pair: usdToTL), lookup: lookup(rate: 40))
        let negative = try ExchangeRatePresentation.make(request: ConversionRequest(amount: decimal("-0.1"), pair: usdToTL), lookup: lookup(rate: decimal("0.2")))
        XCTAssertEqual(zero.copyText, "0 TL")
        XCTAssertEqual(negative.copyText, "-0.02 TL")
    }

    func testTinyNonzeroRateDoesNotFalselyDisplayAsZero() throws {
        let result = try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 1, pair: tlToEuro, isRateQuery: true),
            lookup: lookup(rate: decimal("0.000000000001"), pair: tlToEuro)
        )
        XCTAssertEqual(result.valueText, "1 TL = 0.000000000001 EUR")
        XCTAssertEqual(result.copyText, "0.000000000001 EUR")
    }

    func testInvalidRatesCannotProduceCopyableAnswers() {
        for rate: Decimal in [0, -1, .nan] {
            XCTAssertThrowsError(try ExchangeRatePresentation.make(request: ConversionRequest(amount: 3, pair: usdToTL), lookup: lookup(rate: rate))) {
                XCTAssertEqual($0 as? ExchangeRatePresentationError, .invalidRate)
            }
        }
        let identity = CurrencyPair(base: "TL", quote: "TRY")
        XCTAssertThrowsError(try ExchangeRatePresentation.make(request: ConversionRequest(amount: 1, pair: identity), lookup: lookup(rate: 2, pair: identity))) {
            XCTAssertEqual($0 as? ExchangeRatePresentationError, .invalidRate)
        }
    }

    func testAQuoteForAnotherPairCannotBeUsed() {
        XCTAssertThrowsError(try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL), lookup: lookup(rate: 40, pair: tlToEuro)
        )) {
            XCTAssertEqual($0 as? ExchangeRatePresentationError, .mismatchedPair)
        }
    }

    func testInvalidAmountAndDecimalOverflowOrUnderflowReturnClearErrors() {
        let inputs: [(Decimal, Decimal)] = [(.nan, 40), (decimal("99999999999999999999999999999999999999e127"), 1_000), (decimal("1e-127"), decimal("1e-10"))]
        for (amount, rate) in inputs {
            XCTAssertThrowsError(try ExchangeRatePresentation.make(request: ConversionRequest(amount: amount, pair: usdToTL), lookup: lookup(rate: rate)), "Amount \(amount), rate \(rate)") {
                XCTAssertEqual($0 as? ExchangeRatePresentationError, .amountOutOfRange)
                XCTAssertEqual($0.localizedDescription, "The converted amount is outside the supported decimal range.")
            }
        }
    }

    func testUnitRateCannotLabelAMultipleAsOneUnit() {
        XCTAssertThrowsError(try ExchangeRatePresentation.make(
            request: ConversionRequest(amount: 3, pair: usdToTL, isRateQuery: true), lookup: lookup(rate: 40)
        )) {
            XCTAssertEqual($0 as? ExchangeRatePresentationError, .invalidRateQueryAmount)
        }
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func lookup(rate: Decimal, pair: CurrencyPair? = nil, providers: [String] = ["ECB"],
                        offline: Bool = false, failure: String? = nil) -> RateLookup {
        let quote = ExchangeQuote(pair: pair ?? usdToTL, rate: rate, observedDate: "2026-09-25",
                                  fetchedAt: Date(timeIntervalSince1970: 1_790_780_400), providers: providers)
        return RateLookup(quote: quote, usedOfflineCache: offline, failureDescription: failure)
    }
}
