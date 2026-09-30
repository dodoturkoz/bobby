import Foundation
import XCTest
@testable import BobbyCore

final class InterestReviewInputTests: XCTestCase {
    private let draft = InterestDraft(principal: 500_000, currency: "TRY", annualRatePercent: 42,
                                      duration: InterestDuration(value: 3, unit: .years))

    func testArithmeticPrincipalAndNamedCurrencyProduceFixedBasisExpression() throws {
        let expression = try InterestReviewInput.expression(draft: draft, principalText: "(500k + 250k) * .75",
                                                            currencyText: "Turkish lira", yearBasis: 360)
        XCTAssertEqual(expression, "562500 TL at 42% for 1080 days basis 360")
        let result = try XCTUnwrap(CalculationEngine().evaluate(expression, yearBasis: 366).first)
        XCTAssertEqual(result.kind, .interest)
        XCTAssertEqual(result.interest?.principal, 562_500)
        XCTAssertEqual(result.value, 708_750)
        XCTAssertEqual(result.interest?.yearBasis, 360)
    }

    func testEmptyCurrencyFieldClearsOriginalDraftCurrency() throws {
        let expression = try InterestReviewInput.expression(draft: draft, principalText: "1000",
                                                            currencyText: "  ", yearBasis: 365)
        XCTAssertEqual(expression, "1000 at 42% for 1095 days basis 365")
        XCTAssertNil(CalculationEngine().evaluate(expression).first?.interest?.currency)
    }

    func testExplicitSupportedCurrencyAliasesAndSymbolsAreAccepted() throws {
        for (text, code) in [(" U.S. dollars ", "USD"), ("€", "EUR"), ("₺", "TL"), ("tl", "TL"), ("British pounds", "GBP")] {
            let expression = try InterestReviewInput.expression(draft: draft, principalText: "  1,234.56  ",
                                                                currencyText: text, yearBasis: 365)
            XCTAssertEqual(expression, "1234.56 \(code) at 42% for 1095 days basis 365", text)
        }
    }

    func testZeroAndLeadingDecimalPrincipalAreAllowed() throws {
        XCTAssertEqual(try InterestReviewInput.expression(draft: draft, principalText: "0", currencyText: "USD", yearBasis: 365),
                       "0 USD at 42% for 1095 days basis 365")
        XCTAssertEqual(try InterestReviewInput.expression(draft: draft, principalText: ".75", currencyText: "", yearBasis: 365),
                       "0.75 at 42% for 1095 days basis 365")
    }

    func testMissingPrincipalDoesNotFallBackToTheDraftAmount() {
        for input in ["", " ", "\t"] {
            XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: input,
                                                                    currencyText: "TL", yearBasis: 365)) { error in
                XCTAssertEqual(error as? InterestDraftError, .missingPrincipal, input)
            }
        }
    }

    func testAllNewlineFormsAndIgnoredNotesAreRejected() {
        let inputs = ["note\n100", "100\nCall bank", "100\n", "100\r200", "100\r\n200", "100\u{2028}200",
                      "100\u{2029}200", "100\u{85}200"]
        for input in inputs {
            XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: input,
                                                                    currencyText: "TL", yearBasis: 365)) { error in
                XCTAssertEqual(error as? InterestDraftError, .invalidPrincipal, input)
            }
        }
    }

    func testAssignmentsAreRejectedEvenWhenEngineReturnsOneValue() {
        for input in ["principal = 100", "principal=100", "ödeme_2 = 100", "Result = 100", "100 = 200"] {
            XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: input,
                                                                    currencyText: "TL", yearBasis: 365)) { error in
                XCTAssertEqual(error as? InterestDraftError, .invalidPrincipal, input)
            }
        }
    }

    func testPrincipalRejectsMoneyUnknownVariablesNotesInvalidNumbersAndNegativeValues() {
        let inputs = ["100 TL", "100 USD", "amount * 2", "100 apples", "Call bank", "NaN", "nan", "-100", "100 - 200",
                      "100 / 0", "1,23", "1.234,56", "100 +", "500 USD to TL", "3 years interest at 42%"]
        for input in inputs {
            XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: input,
                                                                    currencyText: "TL", yearBasis: 365)) { error in
                XCTAssertEqual(error as? InterestDraftError, .invalidPrincipal, input)
            }
        }
    }

    func testCurrencyRejectsAmbiguousNamesProseAndNewlines() {
        for input in ["lira", "dollars", "$", "not a currency", "100 USD", "Turkish\nlira", "USD\r", "USD\u{2028}"] {
            XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: "100",
                                                                    currencyText: input, yearBasis: 365)) { error in
                XCTAssertEqual(error as? InterestDraftError, .unsupportedCurrency, input)
            }
        }
    }

    func testInvalidBasisAndRateStillUseDraftValidation() {
        XCTAssertThrowsError(try InterestReviewInput.expression(draft: draft, principalText: "100",
                                                                currencyText: "TL", yearBasis: 0)) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidYearBasis)
        }
        let invalidRate = InterestDraft(principal: nil, currency: nil, annualRatePercent: .nan,
                                        duration: InterestDuration(value: 3, unit: .years))
        XCTAssertThrowsError(try InterestReviewInput.expression(draft: invalidRate, principalText: "100",
                                                                currencyText: "", yearBasis: 365)) { error in
            XCTAssertEqual(error as? InterestDraftError, .invalidRate)
        }
    }

    func testReviewRetainsExactDecimalPrincipalAndRate() throws {
        let preciseDraft = InterestDraft(principal: nil, currency: nil, annualRatePercent: decimal("42.123456789"),
                                         duration: InterestDuration(value: decimal("1.25"), unit: .years))
        let expression = try InterestReviewInput.expression(draft: preciseDraft, principalText: "1234.123456789 + .000000001",
                                                            currencyText: "USD", yearBasis: 360)
        XCTAssertEqual(expression, "1234.12345679 USD at 42.123456789% for 450 days basis 360")
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
