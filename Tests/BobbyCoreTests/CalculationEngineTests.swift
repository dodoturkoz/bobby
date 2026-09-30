import Foundation
import XCTest
@testable import BobbyCore

final class CalculationEngineTests: XCTestCase {
    private let engine = CalculationEngine()

    func testDecimalArithmeticDoesNotIntroduceBinaryFloatingPointError() {
        let results = engine.evaluate("0.1 + 0.2\n19.99 * 3\n1.01 - .99")
        XCTAssertEqual(results.map(\.value), [decimal("0.3"), decimal("59.97"), decimal("0.02")])
    }

    func testPrecedenceUnaryAndRightAssociativePowers() {
        let results = engine.evaluate("2 + 3 * 4\n(2 + 3) * 4\n-2^2\n(-2)^2\n2^3^2\n2^-2")
        XCTAssertEqual(results.map(\.value), [14, 20, -4, 4, 512, decimal(".25")])
    }

    func testPercentAndShorthandHaveStandardScalarMeaning() {
        let results = engine.evaluate("11.5m * 2%\n500K * .75\n1M + 25k\n100 + 10%")
        XCTAssertEqual(results.map(\.value), [230_000, 375_000, 1_025_000, decimal("100.1")])
    }

    func testAssignmentsFollowSourceOrderAndRecalculateFromScratch() {
        let initial = engine.evaluate("price = 10\nprice * 2\nprice = 20\nprice * 2")
        XCTAssertEqual(initial.map(\.value), [10, 20, 20, 40])
        XCTAssertEqual(initial.map(\.lineIndex), [0, 1, 2, 3])
        let changed = engine.evaluate("price = 15\nprice * 2")
        XCTAssertEqual(changed.map(\.value), [15, 30])
        XCTAssertEqual(changed[0].title, "price")
    }

    func testVariablesDoNotLeakAcrossScratchEvaluations() {
        _ = engine.evaluate("principal = 500")
        let result = engine.evaluate("principal * 2")
        XCTAssertEqual(result.first?.kind, .error)
        XCTAssertTrue(result.first?.detail?.contains("Unknown variable") == true)
    }

    func testIncompleteRedefinitionCannotUseStaleVariableValue() {
        let results = engine.evaluate("amount = 10\namount =\namount * 2")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?.kind, .error)
        XCTAssertEqual(results.last?.lineIndex, 2)
    }

    func testMoneyVariablesRetainCurrencyThroughManualDeductions() {
        let results = engine.evaluate("principal = 500k tl\nprincipal * .75\nprincipal + 25k TRY\nprincipal / 500 TL")
        XCTAssertEqual(results.map(\.value), [500_000, 375_000, 525_000, 1_000])
        XCTAssertEqual(results.map(\.currency), ["TRY", "TRY", "TRY", nil])
    }

    func testMoneyAmountsRequireCompatibleArithmetic() {
        let results = engine.evaluate("500 TL + 10 USD\n500 TL * 10 TRY\n500 TL + 10")
        XCTAssertEqual(results.map(\.kind), [.error, .error, .error])
    }

    func testOrdinaryNotesRemainOrdinaryNotes() {
        let results = engine.evaluate("Call the bank tomorrow\n2026 budget\nUSD\n500 apples + 3 oranges\nMeeting at 4 for lunch\n2 + 3")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lineIndex, 5)
        XCTAssertEqual(results[0].value, 5)
    }

    func testIncompleteInputDoesNotShowErrorsWhileTyping() {
        let inputs = ["12 +", "(12 + 3", "value =", ".75 *", "1.", "1,234.",
                      "500 USD to", "500k TL %40", "500k TL %40 yıllık 32",
                      "500k TRY at 40% for"]
        for input in inputs {
            XCTAssertTrue(engine.evaluate(input).isEmpty, "Unexpected result for \(input)")
        }
    }

    func testDivisionByZeroIsAVisibleError() {
        let results = engine.evaluate("10 / (3 - 3)")
        XCTAssertEqual(results.first?.kind, .error)
        XCTAssertEqual(results.first?.detail, "Cannot divide by zero.")
    }

    func testUnsupportedPowersAreVisibleErrors() {
        let results = engine.evaluate("2^.5\n2^101\n0^-1")
        XCTAssertEqual(results.map(\.kind), [.error, .error, .error])
    }

    func testEnglishGroupingIsStrictAndTurkishPunctuationIsNotGuessed() {
        let results = engine.evaluate("1,234.56 + .44\n1,000,000.25\n1,23 + 4\n1.234,56\n12,34,567")
        XCTAssertEqual(results[0].value, 1_235)
        XCTAssertEqual(results[1].value, decimal("1000000.25"))
        XCTAssertEqual(Array(results.dropFirst(2)).map(\.kind), [.error, .error, .error])
        XCTAssertTrue(results[2].detail?.contains("English formatting") == true)
    }

    func testCurrencyPairCanonicalizesBothPositionsCaseInsensitively() {
        XCTAssertEqual(CurrencyPair(base: "tl", quote: "usd"), CurrencyPair(base: "TRY", quote: "USD"))
        XCTAssertEqual(CurrencyPair(base: "usd", quote: "tL"), CurrencyPair(base: "USD", quote: "try"))
        XCTAssertEqual(Set([CurrencyPair(base: "TL", quote: "usd"), CurrencyPair(base: "TRY", quote: "USD")]).count, 1)
    }

    func testConversionsReturnUnresolvedRequestsWithoutRates() {
        let results = engine.evaluate("500 USD to TL\n500 tl to usd\n250 TRY → eur")
        XCTAssertEqual(results.map(\.kind), [.conversion, .conversion, .conversion])
        XCTAssertEqual(results.map(\.conversion), [
            ConversionRequest(amount: 500, pair: CurrencyPair(base: "USD", quote: "TRY")),
            ConversionRequest(amount: 500, pair: CurrencyPair(base: "TRY", quote: "USD")),
            ConversionRequest(amount: 250, pair: CurrencyPair(base: "TRY", quote: "EUR"))
        ])
        XCTAssertTrue(results.allSatisfy { $0.value == nil })
    }

    func testConversionAmountCanBeAnExpression() {
        let results = engine.evaluate("(250 + 250) usd -> TL", rates: [CurrencyPair(base: "USD", quote: "TL"): decimal("40.5")])
        XCTAssertEqual(results.first?.value, 20_250)
        XCTAssertEqual(results.first?.currency, "TRY")
        XCTAssertEqual(results.first?.conversion?.amount, 500)
    }

    func testResolvedConversionAssignmentsRecalculateDependentMoneyExpressions() {
        let text = "budget = 500 USD to TL\nbudget * .75"
        let pair = CurrencyPair(base: "USD", quote: "TRY")
        let first = engine.evaluate(text, rates: [pair: 40])
        XCTAssertEqual(first.map(\.value), [20_000, 15_000])
        XCTAssertEqual(first.map(\.currency), ["TRY", "TRY"])
        XCTAssertNotNil(first[0].conversion)
        let changed = engine.evaluate(text, rates: [pair: 42])
        XCTAssertEqual(changed.map(\.value), [21_000, 15_750])
    }

    func testDependentVariablesWaitQuietlyForUnresolvedRates() {
        let results = engine.evaluate("budget = 500 USD to TL\nnet = budget * .75\nnet * 2")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .conversion)
        XCTAssertNil(results.first?.value)
    }

    func testSameCurrencyConversionNeedsNoRate() {
        let result = engine.evaluate("500 TL to try").first
        XCTAssertEqual(result?.kind, .conversion)
        XCTAssertEqual(result?.value, 500)
        XCTAssertEqual(result?.currency, "TRY")
    }

    func testInvalidExchangeRateIsNotUsed() {
        let result = engine.evaluate("500 USD to TRY", rates: [CurrencyPair(base: "USD", quote: "TRY"): 0]).first
        XCTAssertEqual(result?.kind, .error)
    }

    func testTurkishSimpleInterestShowsGrossInterestAndBalance() {
        let result = engine.evaluate("365k TL %40 yıllık 32 gün").first
        XCTAssertEqual(result?.kind, .interest)
        XCTAssertEqual(result?.value, 12_800)
        XCTAssertEqual(result?.currency, "TRY")
        XCTAssertEqual(result?.interest?.principal, 365_000)
        XCTAssertEqual(result?.interest?.annualRate, decimal(".4"))
        XCTAssertEqual(result?.interest?.days, 32)
        XCTAssertEqual(result?.interest?.yearBasis, 365)
        XCTAssertEqual(result?.interest?.total, 377_800)
        XCTAssertTrue(result?.detail?.contains("Actual/365") == true)
    }

    func testUserExampleUsesActual365AndRoundsOnlyForPresentation() {
        let result = engine.evaluate("500k TL %40 yıllık 32 gün").first
        XCTAssertEqual(rounded(result?.value, scale: 8), decimal("17534.24657534"))
        XCTAssertEqual(rounded(result?.interest?.total, scale: 8), decimal("517534.24657534"))
        XCTAssertNotEqual(result?.value, rounded(result?.value, scale: 8))
    }

    func testInterestSupportsEnglishAndTurkishASCIIWithExplicitBasis() {
        let results = engine.evaluate("90k TRY at 10% for 36 days basis 360\n90k tl %10 yillik 36 gun basis 360")
        XCTAssertEqual(results.map(\.value), [900, 900])
        XCTAssertEqual(results.map { $0.interest?.yearBasis }, [360, 360])
        XCTAssertEqual(results.map { $0.interest?.total }, [90_900, 90_900])
    }

    func testInterestUsesEditableDefaultYearBasis() {
        let result = engine.evaluate("36k TL %10 yıllık 36 gün", yearBasis: 360).first
        XCTAssertEqual(result?.value, 360)
        XCTAssertEqual(result?.interest?.yearBasis, 360)
    }

    func testInterestCanBindAVariableForManualDeduction() {
        let results = engine.evaluate("interest = 365k TL %40 yıllık 32 gün\ninterest * .75")
        XCTAssertEqual(results.map(\.value), [12_800, 9_600])
        XCTAssertEqual(results.map(\.currency), ["TRY", "TRY"])
    }

    func testInterestRejectsInvalidPrincipalDaysAndBasis() {
        let results = engine.evaluate("-500 TL %40 yıllık 32 gün\n500 TL %40 yıllık -32 gün\n500 TL %40 yıllık 32 gün basis 0")
        XCTAssertEqual(results.map(\.kind), [.error, .error, .error])
        XCTAssertEqual(engine.evaluate("500 TL %40 yıllık 32 gün", yearBasis: 0).first?.kind, .error)
    }

    func testInterestDoesNotSilentlyApplyStopaj() {
        XCTAssertTrue(engine.evaluate("500k TL %40 yıllık 32 gün stopaj %15").isEmpty)
    }

    func testPresentationUsesEnglishGroupingWithoutChangingValue() {
        let value = decimal("1234.56789")
        XCTAssertEqual(NumberFormatting.string(value), "1,234.56789")
        XCTAssertEqual(NumberFormatting.string(value, maximumFractionDigits: 2), "1,234.57")
        XCTAssertEqual(value, decimal("1234.56789"))
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func rounded(_ value: Decimal?, scale: Int) -> Decimal? {
        guard var value else { return nil }
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
