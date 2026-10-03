import Foundation
import XCTest
@testable import BobbyCore

final class GoldCalculationEngineTests: XCTestCase {
    private let engine = CalculationEngine()
    private let instant = Date(timeIntervalSince1970: 1_791_000_000)

    func testBareProductRequestsBothPricesWithoutChoosingAScalar() {
        let result = engine.evaluate("çeyrek altın", goldQuotes: [.quarterCoin: quote()]).first
        XCTAssertEqual(result?.kind, .gold)
        XCTAssertEqual(result?.gold, GoldRequest(product: .quarterCoin))
        XCTAssertEqual(result?.currency, "TRY")
        XCTAssertNil(result?.value)
        XCTAssertNil(result?.conversion)
    }

    func testMissingQuoteReturnsARequestAndNeverInventsAPrice() {
        let result = engine.evaluate("2 ceyrek altin buy").first
        XCTAssertEqual(result?.kind, .gold)
        XCTAssertEqual(result?.gold, GoldRequest(product: .quarterCoin, quantity: 2, side: .dealerBuy))
        XCTAssertNil(result?.value)
    }

    func testDealerSidesResolveAsDecimalMoneyAndRetainTheRequest() {
        let results = engine.evaluate("2.5 çeyrek altın alış\n2.5 ceyrek altin sell",
                                      goldQuotes: [.quarterCoin: quote(buy: decimal("10516.94"), sell: decimal("11050.5"))])
        XCTAssertEqual(results.map(\.kind), [.gold, .gold])
        XCTAssertEqual(results.map(\.value), [decimal("26292.35"), decimal("27626.25")])
        XCTAssertEqual(results.map(\.currency), ["TRY", "TRY"])
        XCTAssertEqual(results.map { $0.gold?.side }, [.dealerBuy, .dealerSell])
        XCTAssertEqual(results.map { $0.gold?.quantity }, [decimal("2.5"), decimal("2.5")])
    }

    func testQuantitiesUseExistingVariablesArithmeticAndEnglishFormatting() {
        let results = engine.evaluate("miktarı = 2\n(miktarı + 1) * .5 gram altın buy\n1,234.5 gram altin sell",
                                      goldQuotes: [.gram: quote(product: .gram, buy: decimal("4000.25"), sell: decimal("4050.5"))])
        XCTAssertEqual(results.map(\.value), [2, decimal("6000.375"), decimal("5000342.25")])
        XCTAssertEqual(results[1].gold?.quantity, decimal("1.5"))
        XCTAssertEqual(results[2].gold?.quantity, decimal("1234.5"))
    }

    func testExplicitSideAssignmentWaitsThenRecalculatesDependentMoneyValues() {
        let text = "valuation = 2 çeyrek altın sell\nnet = valuation * .75\nnet + 10 TL"
        let pending = engine.evaluate(text)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.kind, .gold)
        XCTAssertNil(pending.first?.value)

        let results = engine.evaluate(text, goldQuotes: [.quarterCoin: quote(buy: 10_000, sell: 11_000)])
        XCTAssertEqual(results.map(\.value), [22_000, 16_500, 16_510])
        XCTAssertEqual(results.map(\.currency), ["TRY", "TRY", "TRY"])
        XCTAssertEqual(results.first?.gold?.side, .dealerSell)

        let changed = engine.evaluate(text, goldQuotes: [.quarterCoin: quote(buy: 11_000, sell: 12_000)])
        XCTAssertEqual(changed.map(\.value), [24_000, 18_000, 18_010])
    }

    func testAssignmentWithoutASideHasAClearErrorEvenWhenQuantityIsPending() {
        let results = engine.evaluate("quantity = 3 USD to TL\nvaluation = quantity ceyrek altin")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?.kind, .error)
        XCTAssertTrue(results.last?.detail?.contains("Choose a gold quote side") == true)
        XCTAssertNil(results.last?.gold)
    }

    func testAmbiguousAssignmentDoesNotReuseAnEarlierValue() {
        let results = engine.evaluate("valuation = 10\nvaluation = ceyrek altin\nvaluation * 2",
                                      goldQuotes: [.quarterCoin: quote()])
        XCTAssertEqual(results.map(\.kind), [.value, .error, .error])
        XCTAssertTrue(results[1].detail?.contains("buy") == true)
        XCTAssertTrue(results[2].detail?.contains("Unknown variable") == true)
    }

    func testProductAndSideWordsNeverBecomeVariableDependencies() {
        let text = "buy = 3 EUR to USD\naltin = 3 USD to TL\nceyrek = 3 EUR to TL\nceyrek altin buy"
        let results = engine.evaluate(text, goldQuotes: [.quarterCoin: quote(buy: 10_000, sell: 11_000)])
        XCTAssertEqual(results.map(\.lineIndex), [0, 1, 2, 3])
        XCTAssertEqual(results.last?.kind, .gold)
        XCTAssertEqual(results.last?.value, 10_000)
    }

    func testOnlyQuantityVariablesWaitForAnUnresolvedQuote() {
        let text = "quantity = 3 EUR to USD\nquantity gram altin buy\nceyrek altin sell"
        let results = engine.evaluate(text, goldQuotes: [.quarterCoin: quote()])
        XCTAssertEqual(results.map(\.lineIndex), [0, 2])
        XCTAssertEqual(results.last?.kind, .gold)
    }

    func testGoldQuantitiesCannotBeNegativeOrMoneyAmounts() {
        let results = engine.evaluate("-2 ceyrek altin\n500 TL ceyrek altin buy\namount = 2 TL\namount gram altin sell")
        XCTAssertEqual(results.map(\.kind), [.error, .error, .value, .error])
        XCTAssertTrue(results[0].detail?.contains("zero or greater") == true)
        XCTAssertTrue(results[1].detail?.contains("plain numbers") == true)
        XCTAssertTrue(results[3].detail?.contains("plain numbers") == true)
    }

    func testZeroQuantityHasAnExactZeroValueWhenASideIsSelected() {
        let result = engine.evaluate("0 ceyrek altin buy", goldQuotes: [.quarterCoin: quote()]).first
        XCTAssertEqual(result?.kind, .gold)
        XCTAssertEqual(result?.value, 0)
        XCTAssertEqual(result?.gold?.quantity, 0)
    }

    func testEnglishPunctuationRemainsStrictForGoldQuantity() {
        let results = engine.evaluate("1,23 gram altin buy\n1.234,56 gram altin sell")
        XCTAssertEqual(results.map(\.kind), [.error, .error])
        XCTAssertTrue(results.allSatisfy { $0.detail?.contains("English formatting") == true })
    }

    func testGoldNotesAndIncompletePhrasesStayQuiet() {
        for input in ["altın", "gold", "ceyrek", "ceyrek alt", "I have 2 ceyrek altin", "ceyrek altin tomorrow",
                      "buy ceyrek altin", "(2 + 3 ceyrek altin buy", "2 + ceyrek altin buy"] {
            XCTAssertTrue(engine.evaluate(input).isEmpty, input)
        }
    }

    func testGoldQuotesAreValidatedBeforeUse() {
        let invalidQuotes = [
            quote(product: .gram), quote(buy: 0), quote(sell: .nan), quote(buy: 12_000, sell: 11_000)
        ]
        for quote in invalidQuotes {
            let result = engine.evaluate("ceyrek altin buy", goldQuotes: [.quarterCoin: quote]).first
            XCTAssertEqual(result?.kind, .error)
            XCTAssertNil(result?.value)
            XCTAssertNil(result?.gold)
        }
    }

    func testGoldMultiplicationCannotWrapExtremeDecimalExponents() {
        let large = Decimal(sign: .plus, exponent: 127, significand: 1)
        let result = engine.evaluate("10^100 gram altin sell", goldQuotes: [.gram: quote(product: .gram, buy: large, sell: large)]).first
        XCTAssertEqual(result?.kind, .error)
        XCTAssertNil(result?.value)
    }

    func testOnlyTheSelectedSideDeterminesAScalarGoldValuation() {
        let text = "valuation = 10^100 gram altin buy\nvaluation * .1"
        let quote = quote(product: .gram,
                          buy: Decimal(sign: .plus, exponent: 65, significand: 1),
                          sell: Decimal(sign: .plus, exponent: 66, significand: 1))
        let results = engine.evaluate(text, goldQuotes: [.gram: quote])
        XCTAssertEqual(results.map(\.kind), [.gold, .value])
        XCTAssertEqual(results.first?.value.map { NSDecimalNumber(decimal: $0).stringValue }, "1" + String(repeating: "0", count: 165))
        XCTAssertEqual(results.last?.value.map { NSDecimalNumber(decimal: $0).stringValue }, "1" + String(repeating: "0", count: 164))
        XCTAssertEqual(results.first?.gold?.side, .dealerBuy)
    }

    func testExistingCurrencyVariablesAndExplicitPairsRemainUnchanged() {
        let results = engine.evaluate("EUR = 3\nEUR USD\nEUR to USD\ninterest = 365k TL %40 yıllık 32 gün\ninterest * .75",
                                      rates: [CurrencyPair(base: "EUR", quote: "USD"): 2],
                                      goldQuotes: [.quarterCoin: quote()])
        XCTAssertEqual(results.map(\.kind), [.value, .value, .conversion, .interest, .value])
        XCTAssertEqual(results.map(\.value), [3, 3, 2, 12_800, 9_600])
        XCTAssertEqual(results[1].currency, "USD")
        XCTAssertEqual(results[2].conversion?.isRateQuery, true)
        XCTAssertTrue(results.allSatisfy { $0.gold == nil })
    }

    private func quote(product: GoldProduct = .quarterCoin, buy: Decimal = 10_000, sell: Decimal = 11_000) -> GoldQuote {
        GoldQuote(product: product, dealerBuy: buy, dealerSell: sell, observedAt: instant,
                  fetchedAt: instant, productLabel: product.providerName)
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
