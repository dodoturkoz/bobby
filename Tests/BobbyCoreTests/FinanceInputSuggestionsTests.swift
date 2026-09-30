import Foundation
import XCTest
@testable import BobbyCore

final class FinanceInputSuggestionsTests: XCTestCase {
    func testMissingPrincipalProducesReviewRatherThanAnInventedAnswer() throws {
        let suggestion = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "3 years interest at 42%"))
        XCTAssertNil(suggestion.interest.principal)
        XCTAssertNil(suggestion.interest.currency)
        XCTAssertEqual(suggestion.interest.annualRatePercent, 42)
        XCTAssertEqual(suggestion.interest.duration, InterestDuration(value: 3, unit: .years))
        XCTAssertTrue(suggestion.detail.contains("enter a principal"))
        XCTAssertThrowsError(try suggestion.interest.canonicalExpression()) { error in
            XCTAssertEqual(error as? InterestDraftError, .missingPrincipal)
        }
    }

    func testSeveralExplicitEnglishFormsProduceTheSameDraft() throws {
        let forms = [
            "3 years interest at 42%",
            "3-year interest at 42 percent",
            "interest for 3 years at 42%",
            "simple interest at 42% annually for 3 years",
            "  INTEREST FOR 3 YEARS AT 42% PER YEAR  "
        ]
        let expected = InterestDraft(principal: nil, currency: nil, annualRatePercent: 42,
                                    duration: InterestDuration(value: 3, unit: .years))
        for form in forms {
            XCTAssertEqual(FinanceInputSuggestions.suggestion(for: form)?.interest, expected, form)
        }
    }

    func testRequestedTurkishPhraseRequiresTheSameExplicitReview() throws {
        let forms = ["3 yıllık faiz yüzde 42", "3 yillik faiz yuzde 42", "3 yıl faiz %42", "3 yıllık faiz yüzde 42'den"]
        for form in forms {
            let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: form)?.interest, form)
            XCTAssertNil(draft.principal)
            XCTAssertEqual(draft.annualRatePercent, 42)
            XCTAssertEqual(draft.duration, InterestDuration(value: 3, unit: .years))
            XCTAssertTrue(draft.reviewDetail().contains("annual 42%"))
            XCTAssertTrue(draft.reviewDetail().contains("No compounding"))
        }
    }

    func testCompleteEnglishPhraseKeepsPrincipalCurrencyAndDecimalRate() throws {
        let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 500k TL at 42.5% for 3 years")?.interest)
        XCTAssertEqual(draft.principal, 500_000)
        XCTAssertEqual(draft.currency, "TRY")
        XCTAssertEqual(draft.annualRatePercent, decimal("42.5"))
        XCTAssertEqual(try draft.canonicalExpression(), "500000 TL at 42.5% for 1095 days basis 365")
        let result = try XCTUnwrap(CalculationEngine().evaluate(try draft.canonicalExpression()).first)
        XCTAssertEqual(result.kind, .interest)
        XCTAssertEqual(result.value, 637_500)
        XCTAssertEqual(result.interest?.total, 1_137_500)
    }

    func testCompletePhraseSupportsUnambiguousCurrencyNamesAndOrder() throws {
        let forms = [
            "simple interest on 500k Turkish lira at 42% for 3 years",
            "interest on 500k tl for 3 years at 42 percent",
            "500k TRY at 42% for 3 years"
        ]
        let expected = InterestDraft(principal: 500_000, currency: "TRY", annualRatePercent: 42,
                                    duration: InterestDuration(value: 3, unit: .years))
        for form in forms {
            XCTAssertEqual(FinanceInputSuggestions.suggestion(for: form)?.interest, expected, form)
        }
    }

    func testPrincipalAliasesIncludeDottedNamesAndExplicitSymbols() throws {
        let aliases = [("U.S. dollars", "USD"), ("€", "EUR"), ("₺", "TRY"), ("US$", "USD")]
        for (alias, code) in aliases {
            let text = "interest on 500 \(alias) at 42% for 3 years"
            let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: text)?.interest, text)
            XCTAssertEqual(draft.currency, code, text)
            let result = try XCTUnwrap(CalculationEngine().evaluate(try draft.canonicalExpression()).first, text)
            XCTAssertEqual(result.interest?.currency, code, text)
        }
        XCTAssertNil(FinanceInputSuggestions.suggestion(for: "interest on 500 $ at 42% for 3 years"))
    }

    func testFractionalYearsUseExplicitReviewedBasis() throws {
        let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 100 USD at 10% for 1.5 years")?.interest)
        XCTAssertEqual(try draft.canonicalExpression(yearBasis: 360), "100 USD at 10% for 540 days basis 360")
        XCTAssertEqual(try draft.canonicalExpression(yearBasis: 366), "100 USD at 10% for 549 days basis 366")
        XCTAssertTrue(draft.reviewDetail(yearBasis: 360).contains("Each year is 360 days (540 days total)"))
        XCTAssertTrue(draft.reviewDetail(yearBasis: 360).contains("Actual/360"))
        XCTAssertEqual(CalculationEngine().evaluate(try draft.canonicalExpression(yearBasis: 360), yearBasis: 365).first?.value, 15)
    }

    func testDaysRemainElapsedDaysRatherThanBeingScaled() throws {
        let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 500k TL at 42% for 32 days")?.interest)
        XCTAssertEqual(try draft.canonicalExpression(yearBasis: 360), "500000 TL at 42% for 32 days basis 360")
        XCTAssertEqual(draft.duration, InterestDuration(value: 32, unit: .days))
        XCTAssertFalse(draft.reviewDetail(yearBasis: 360).contains("Each year"))
        let turkish = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "32 günlük faiz yüzde 42")?.interest)
        XCTAssertEqual(turkish.duration, InterestDuration(value: 32, unit: .days))
    }

    func testEnglishGroupingShorthandAndLeadingDecimalsKeepPrecision() throws {
        let forms: [(String, Decimal)] = [
            ("interest on 1,234.56 EUR at .75% for 1 year", decimal("1234.56")),
            ("interest on .75 USD at 1.25% for 3 days", decimal(".75")),
            ("interest on 1.25M TL at 42% for 3 years", 1_250_000)
        ]
        for (form, expectedPrincipal) in forms {
            let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: form)?.interest, form)
            XCTAssertEqual(draft.principal, expectedPrincipal, form)
            let expression = try draft.canonicalExpression()
            let result = try XCTUnwrap(CalculationEngine().evaluate(expression).first, expression)
            XCTAssertEqual(result.kind, .interest, expression)
            XCTAssertEqual(result.interest?.principal, expectedPrincipal, expression)
        }
    }

    func testEnteredPrincipalAndCurrencyReplaceReviewedDefaults() throws {
        let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 500k TL at 42% for 3 years")?.interest)
        XCTAssertEqual(try draft.canonicalExpression(principal: 1_000, currency: "euro", yearBasis: 360),
                       "1000 EUR at 42% for 1080 days basis 360")
        let incomplete = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "3 years interest at 42%")?.interest)
        XCTAssertEqual(try incomplete.canonicalExpression(principal: 1_000, currency: "tl"),
                       "1000 TL at 42% for 1095 days basis 365")
    }

    func testExplicitNegativeAndZeroRatesAreNotChanged() throws {
        let negative = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 100 USD at -2% for 1 year")?.interest)
        XCTAssertEqual(negative.annualRatePercent, -2)
        XCTAssertEqual(CalculationEngine().evaluate(try negative.canonicalExpression()).first?.value, -2)
        let zero = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 0 TL at 0% for 0 days")?.interest)
        XCTAssertEqual(CalculationEngine().evaluate(try zero.canonicalExpression()).first?.value, 0)
    }

    func testExistingDocumentedSyntaxDoesNotReceiveAReviewPrompt() {
        let forms = ["500k TL at 42% for 32 days", "500k TL %42 yıllık 32 gün", "500 USD to TL", "100 * .75"]
        for form in forms {
            XCTAssertNil(FinanceInputSuggestions.suggestion(for: form), form)
        }
    }

    func testOrdinaryNotesAndLongerProseNeverBecomeFinanceSuggestions() {
        let notes = [
            "Ask about 3 years interest at 42% tomorrow",
            "3 years interest at 42% sounds too high",
            "The bank offers interest on 500k TL at 42% for 3 years",
            "Remember to calculate interest",
            "Meeting at 3 for 42 days",
            "3 years budget at 42%",
            "interest on oranges at 42% for 3 years",
            "3 years interest at 42%\nCall bank",
            "result = interest on 500k TL at 42% for 3 years",
            String(repeating: " ", count: 513) + "not a finance phrase"
        ]
        for note in notes {
            XCTAssertNil(FinanceInputSuggestions.suggestion(for: note), note)
        }
    }

    func testIncompleteInputRemainsQuietUntilRateAndDurationAreExplicit() {
        let forms = ["3 years interest", "3 years interest at", "3 years interest at 42", "3 years interest at 42.",
                     "interest on 500k TL at 42%", "interest on 500k TL at 42% for", "interest on 500k TL at 42% for 3",
                     "3 yıllık faiz yüzde", "3 yıllık faiz yüzde 42."]
        for form in forms {
            XCTAssertNil(FinanceInputSuggestions.suggestion(for: form), form)
        }
    }

    func testUnsupportedFinancialAssumptionsAreNotSilentlyConverted() {
        let forms = [
            "compound interest on 500k TL at 42% for 3 years",
            "interest on 500k TL at 42% for 3 months",
            "interest on 500k TL at 42% monthly for 3 years",
            "3 years interest at 42% compounded annually",
            "interest on 500k lira at 42% for 3 years",
            "interest on 500k dollars at 42% for 3 years",
            "interest on 500k apples at 42% for 3 years",
            "interest on principal at 42% for 3 years",
            "interest on 500k TL at 42 for 3 years"
        ]
        for form in forms {
            XCTAssertNil(FinanceInputSuggestions.suggestion(for: form), form)
        }
    }

    func testTurkishNumberPunctuationIsNeverGuessed() {
        let forms = ["interest on 1.234,56 TL at 42% for 3 years", "interest on 1,23 TL at 42% for 3 years",
                     "3 years interest at 42,5%", "1,5 yıllık faiz yüzde 42", "3 years interest at 1,23%"]
        for form in forms {
            XCTAssertNil(FinanceInputSuggestions.suggestion(for: form), form)
        }
    }

    func testReviewRejectsInvalidOverridesRatherThanProducingExecutableSyntax() {
        let valid = InterestDraft(principal: 100, currency: nil, annualRatePercent: 42,
                                  duration: InterestDuration(value: 3, unit: .years))
        XCTAssertThrowsError(try valid.canonicalExpression(principal: -1)) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidPrincipal)
        }
        XCTAssertThrowsError(try valid.canonicalExpression(principal: .nan)) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidPrincipal)
        }
        XCTAssertThrowsError(try valid.canonicalExpression(yearBasis: 0)) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidYearBasis)
        }
        XCTAssertThrowsError(try valid.canonicalExpression(currency: "lira")) { error in
            XCTAssertEqual(error as? InterestDraftError, .unsupportedCurrency)
        }
        let negativeDuration = InterestDraft(principal: 100, currency: nil, annualRatePercent: 42,
                                            duration: InterestDuration(value: -3, unit: .years))
        XCTAssertThrowsError(try negativeDuration.canonicalExpression()) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidDuration)
        }
        let invalidRate = InterestDraft(principal: 100, currency: nil, annualRatePercent: .nan,
                                       duration: InterestDuration(value: 3, unit: .years))
        XCTAssertThrowsError(try invalidRate.canonicalExpression()) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidRate)
        }
    }

    func testReviewKeepsUnroundedRateAndPrincipalInCanonicalExpression() throws {
        let draft = try XCTUnwrap(FinanceInputSuggestions.suggestion(for: "interest on 1234.123456789 TL at 42.123456789% for 3 years")?.interest)
        XCTAssertEqual(try draft.canonicalExpression(), "1234.123456789 TL at 42.123456789% for 1095 days basis 365")
        let result = try XCTUnwrap(CalculationEngine().evaluate(try draft.canonicalExpression()).first)
        XCTAssertEqual(result.interest?.principal, decimal("1234.123456789"))
        XCTAssertEqual(result.interest?.annualRate, decimal(".42123456789"))
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
