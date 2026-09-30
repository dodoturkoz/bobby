import Foundation
import XCTest
@testable import BobbyCore

final class CalculationFlexibilityTests: XCTestCase {
    private let engine = CalculationEngine()
    private let usdTRY = CurrencyPair(base: "USD", quote: "TRY")

    func testCompleteCurrencyPairsRequestOneUnitInsteadOfAnUnknownVariable() throws {
        for input in ["USD TL", "usd Turkish lira", "USD to TRY", "USD/TRY", "USD → tl"] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .conversion, input)
            XCTAssertEqual(result.conversion?.amount, 1, input)
            XCTAssertEqual(result.conversion?.pair, usdTRY, input)
            XCTAssertEqual(result.conversion?.isRateQuery, true, input)
            XCTAssertNil(result.value, input)
        }
        let result = try XCTUnwrap(engine.evaluate("TL euro").first)
        XCTAssertEqual(result.conversion?.pair, CurrencyPair(base: "TRY", quote: "EUR"))
        XCTAssertEqual(result.conversion?.isRateQuery, true)
    }

    func testNamedCurrencyAndCompactAmountsUseTheSameDecimalConversion() throws {
        let inputs = ["3 USD to Turkish lira", "3 US dollars in Turkish liras",
                      "3 U.S. dollars into Turkish lira", "3USD to TL", "US$3 to ₺"]
        for input in inputs {
            let result = try XCTUnwrap(engine.evaluate(input, rates: [usdTRY: decimal("40.5")]).first, input)
            XCTAssertEqual(result.kind, .conversion, input)
            XCTAssertEqual(result.value, decimal("121.5"), input)
            XCTAssertEqual(result.currency, "TRY", input)
            XCTAssertEqual(result.conversion?.amount, 3, input)
            XCTAssertEqual(result.conversion?.isRateQuery, false, input)
        }
    }

    func testUnicodeArithmeticRemainsAvailableInsideNamedCurrencyConversions() throws {
        for (input, amount) in [("(2 × 3) USD to Turkish lira", Decimal(6)),
                                ("(100 ÷ 4) USD to Turkish lira", Decimal(25)),
                                ("(100 − 25) USD to Turkish lira", Decimal(75))] {
            let result = try XCTUnwrap(engine.evaluate(input, rates: [usdTRY: 40]).first, input)
            XCTAssertEqual(result.kind, .conversion, input)
            XCTAssertEqual(result.conversion?.amount, amount, input)
            XCTAssertEqual(result.value, amount * 40, input)
        }
    }

    func testAmbiguousCurrencyRequiresConfirmationEvenWhenRatesAreAlreadyAvailable() throws {
        for input in ["3 USD to lira", "3 dollars to TL", "$3 to TL", "3 dollars to liras", "USD lira"] {
            let result = try XCTUnwrap(engine.evaluate(input, rates: [usdTRY: 40]).first, input)
            XCTAssertEqual(result.kind, .suggestion, input)
            XCTAssertNotNil(result.suggestion, input)
            XCTAssertNil(result.value, input)
            XCTAssertNil(result.conversion, "Must not request a rate before confirmation: \(input)")
            XCTAssertNil(result.interest, input)
        }
    }

    func testMalformedAmountIsAnErrorBeforeAnAmbiguousCurrencyProposal() throws {
        for input in ["1,23 USD to lira", "1.234,56 USD to lira", "3, USD to lira", "3.. USD to lira"] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .error, input)
            XCTAssertTrue(result.detail?.contains("English formatting") == true, input)
            XCTAssertNil(result.suggestion, input)
            XCTAssertNil(result.conversion, input)
        }
    }

    func testIncompleteAmountsDoNotOfferCurrencyConfirmation() {
        for input in [". USD to lira", "3. USD to lira", "3 + USD to lira", "3 / USD to lira",
                      "(3 + 2 USD to lira", "3 USD to", "3 USD to Turkish", "USD Turkish", "USD to"] {
            XCTAssertTrue(engine.evaluate(input).isEmpty, input)
        }
    }

    func testOrdinaryCurrencyNotesDoNotBecomeUnknownVariableErrors() {
        for input in ["save USD to TL", "compare USD EUR", "buy USD to TL", "amount USD to TL",
                      "Please convert 3 USD to TL", "The exchange rate is USD to TL", "Travel from USD to Turkish lira"] {
            XCTAssertTrue(engine.evaluate(input).isEmpty, input)
        }
    }

    func testUnknownVariableInAnExplicitArithmeticAmountStillShowsAnError() throws {
        let result = try XCTUnwrap(engine.evaluate("amount * .75 USD to euros").first)
        XCTAssertEqual(result.kind, .error)
        XCTAssertTrue(result.detail?.contains("Unknown variable: amount") == true)
        XCTAssertNil(result.conversion)
    }

    func testUnsupportedCurrencyCodesCannotCreateAConversionOrIdentityRate() {
        for input in ["3 XYZ to TL", "3 USD to XYZ", "3 XYZ to XYZ", "XYZ USD", "USD XYZ"] {
            let results = engine.evaluate(input)
            XCTAssertTrue(results.allSatisfy { $0.conversion == nil }, input)
            XCTAssertTrue(results.allSatisfy { $0.value == nil }, input)
        }
    }

    func testSameCurrencyRateQueryHasIdentityValueWithoutNetworkWork() throws {
        let result = try XCTUnwrap(engine.evaluate("TRY TL").first)
        XCTAssertEqual(result.kind, .conversion)
        XCTAssertEqual(result.value, 1)
        XCTAssertEqual(result.currency, "TRY")
        XCTAssertEqual(result.conversion?.isRateQuery, true)
        let ambiguous = try XCTUnwrap(engine.evaluate("lira TL").first)
        XCTAssertEqual(ambiguous.kind, .suggestion)
        XCTAssertNil(ambiguous.value)
        XCTAssertNil(ambiguous.conversion)
    }

    func testKnownCurrencyLookingVariablesKeepTheirEarlierMoneyMeaning() throws {
        for (name, destination) in [("EUR", "USD"), ("TL", "EUR")] {
            let results = engine.evaluate("\(name) = 3\n\(name) \(destination)")
            XCTAssertEqual(results.count, 2)
            let result = try XCTUnwrap(results.last)
            XCTAssertEqual(result.kind, .value)
            XCTAssertEqual(result.value, 3)
            XCTAssertEqual(result.currency, destination)
            XCTAssertNil(result.conversion)
        }
    }

    func testExplicitPairSeparatorsRemainRateQueriesWhenACurrencyLookingVariableExists() throws {
        let pair = CurrencyPair(base: "EUR", quote: "USD")
        for input in ["EUR to USD", "EUR/USD", "EUR → USD"] {
            let result = try XCTUnwrap(engine.evaluate("EUR = 3\n\(input)", rates: [pair: decimal("1.25")]).last, input)
            XCTAssertEqual(result.kind, .conversion, input)
            XCTAssertEqual(result.conversion?.amount, 1, input)
            XCTAssertEqual(result.conversion?.isRateQuery, true, input)
            XCTAssertEqual(result.value, decimal("1.25"), input)
        }
    }

    func testNamedCurrencyDestinationRemainsARateQueryWhenItWasNotAnExistingMoneySuffix() throws {
        let result = try XCTUnwrap(engine.evaluate("EUR = 3\nEUR euro").last)
        XCTAssertEqual(result.kind, .conversion)
        XCTAssertEqual(result.conversion?.pair, CurrencyPair(base: "EUR", quote: "EUR"))
        XCTAssertEqual(result.conversion?.amount, 1)
        XCTAssertEqual(result.conversion?.isRateQuery, true)
        XCTAssertEqual(result.value, 1)
    }

    func testPendingCurrencyLookingVariableDoesNotBlockIndependentAmountConversions() throws {
        let results = engine.evaluate("USD = 3 EUR to USD\n10 USD to TL", rates: [usdTRY: 40])
        XCTAssertEqual(results.map(\.lineIndex), [0, 1])
        let result = try XCTUnwrap(results.last)
        XCTAssertEqual(result.kind, .conversion)
        XCTAssertEqual(result.conversion?.amount, 10)
        XCTAssertEqual(result.conversion?.pair, usdTRY)
        XCTAssertEqual(result.value, 400)
    }

    func testPendingCurrencyLookingVariableOnlyBlocksItsWhitespaceVariableUse() throws {
        let results = engine.evaluate("USD = 3 EUR to USD\nUSD to EUR\nUSD EUR")
        XCTAssertEqual(results.map(\.lineIndex), [0, 1])
        let rate = try XCTUnwrap(results.last)
        XCTAssertEqual(rate.kind, .conversion)
        XCTAssertEqual(rate.conversion?.amount, 1)
        XCTAssertEqual(rate.conversion?.pair, CurrencyPair(base: "USD", quote: "EUR"))
        XCTAssertEqual(rate.conversion?.isRateQuery, true)
    }

    func testAmbiguousConversionAssignmentWaitsRatherThanUsingTheOldValue() throws {
        let pending = engine.evaluate("budget = 100 TL\nbudget = 3 USD to lira\nbudget * .75", rates: [usdTRY: 40])
        XCTAssertEqual(pending.map(\.kind), [.value, .suggestion])
        XCTAssertEqual(pending.map(\.lineIndex), [0, 1])
        XCTAssertNil(pending.last?.value)
        XCTAssertNil(pending.last?.conversion)
        let confirmed = engine.evaluate("budget = 100 TL\nbudget = 3 USD to TL\nbudget * .75", rates: [usdTRY: 40])
        XCTAssertEqual(confirmed.map(\.value), [100, 120, 90])
        XCTAssertEqual(confirmed.map(\.currency), ["TRY", "TRY", "TRY"])
    }

    func testFlexibleConversionAssignmentsWaitForRatesAndThenRecalculateInSourceOrder() {
        let text = "budget = 3 US dollars in Turkish liras\nnet = budget * .75\nnet + 10 TL"
        let pending = engine.evaluate(text)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.kind, .conversion)
        let first = engine.evaluate(text, rates: [usdTRY: 40])
        XCTAssertEqual(first.map(\.value), [120, 90, 100])
        let changed = engine.evaluate(text, rates: [usdTRY: 42])
        XCTAssertEqual(changed.map(\.value), [126, decimal("94.5"), decimal("104.5")])
    }

    func testAConflictingMoneyVariableIsRejectedBeforeOfferingCurrencyConfirmation() throws {
        let result = try XCTUnwrap(engine.evaluate("budget = 10 EUR\nbudget USD to lira").last)
        XCTAssertEqual(result.kind, .error)
        XCTAssertTrue(result.detail?.contains("must match USD") == true)
        XCTAssertNil(result.suggestion)
        XCTAssertNil(result.conversion)
    }

    func testRecognizedInterestPhrasesDoNotCalculateBeforeReview() throws {
        for input in ["3 years interest at 42%", "3 yıllık faiz yüzde 42'den",
                      "interest on 500k TL at 42% for 3 years",
                      "interest on 500k U.S. dollars at 42% for 3 years"] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .suggestion, input)
            XCTAssertNil(result.value, input)
            XCTAssertNil(result.interest, input)
            XCTAssertNil(result.conversion, input)
            guard case .interest = result.suggestion else {
                XCTFail("Expected an interest review for \(input)")
                continue
            }
        }
    }

    func testInterestSuggestionAssignmentDoesNotCreateAUsableAmountBeforeReview() {
        let results = engine.evaluate("profit = 3 years interest at 42%\nprofit * 2")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .suggestion)
        XCTAssertNil(results.first?.value)
    }

    func testCompleteDocumentedInterestSyntaxStillCalculatesImmediately() throws {
        for input in ["500k TL at 42% for 32 days", "500k TL %42 yıllık 32 gün"] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .interest, input)
            XCTAssertNil(result.suggestion, input)
            XCTAssertEqual(result.interest?.principal, 500_000, input)
            XCTAssertEqual(result.interest?.annualRate, decimal(".42"), input)
            XCTAssertEqual(result.interest?.days, 32, input)
            XCTAssertEqual(result.interest?.yearBasis, 365, input)
        }
    }

    func testNegativePowerCanRecoverARepresentableReciprocalFromAnUnderflowingIntermediate() throws {
        for (input, zeros) in [(".01^-65", 130), (".01^-80", 160), (".01^-64", 128), (".1^-100", 100)] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .value, input)
            XCTAssertEqual(result.value, decimal("1" + String(repeating: "0", count: zeros)), input)
        }
    }

    func testNegativeBaseRetainsItsSignWhenNegativePowerNeedsRangeFallback() throws {
        let odd = try XCTUnwrap(engine.evaluate("(-.01)^-65").first)
        XCTAssertEqual(odd.kind, .value)
        XCTAssertEqual(odd.value, decimal("-1" + String(repeating: "0", count: 130)))
        let even = try XCTUnwrap(engine.evaluate("(-.01)^-64").first)
        XCTAssertEqual(even.kind, .value)
        XCTAssertEqual(even.value, decimal("1" + String(repeating: "0", count: 128)))
    }

    func testOrdinaryNegativePowersKeepTheirDecimalPrecision() {
        let results = engine.evaluate("3^-2\n2^-3\n10^-2")
        XCTAssertEqual(results.map(\.kind), [.value, .value, .value])
        XCTAssertEqual(results.map(\.value), [decimal("0.11111111111111111111111111111111111111"), decimal(".125"), decimal(".01")])
    }

    func testPowerFallbackCannotTurnTrueOverflowOrUnderflowIntoAnAnswer() throws {
        for input in [".01^65", ".01^-83", "100^-65", "1000^-100", "1000^100"] {
            let result = try XCTUnwrap(engine.evaluate(input).first, input)
            XCTAssertEqual(result.kind, .error, input)
            XCTAssertNil(result.value, input)
            XCTAssertTrue(result.detail?.contains("outside the supported decimal range") == true, input)
        }
        let zero = try XCTUnwrap(engine.evaluate("0^-1").first)
        XCTAssertEqual(zero.kind, .error)
        XCTAssertEqual(zero.detail, "Cannot divide by zero.")
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
