import Foundation
import XCTest
@testable import BobbyCore

final class CalculationPresentationTests: XCTestCase {
    private let engine = CalculationEngine()

    func testArithmeticDisplaysCopyableValueInsteadOfSemanticTitle() throws {
        let result = try evaluation("11.5m * 2%")

        XCTAssertEqual(result.title, "Result")
        XCTAssertEqual(CalculationPresentation.valueText(result), "230,000")
        XCTAssertEqual(CalculationPresentation.detail(result), "")
        XCTAssertEqual(CalculationPresentation.tooltip(result), "230000")
        XCTAssertEqual(try evaluation(CalculationPresentation.valueText(result)).value, result.value)
    }

    func testAssignmentDisplaysItsValueAndTooltipPreservesFullPrecision() throws {
        let result = try evaluation("monthly = 100 / 3")

        XCTAssertEqual(result.title, "monthly")
        XCTAssertEqual(CalculationPresentation.valueText(result), "33.33333333")
        XCTAssertEqual(
            CalculationPresentation.tooltip(result),
            NSDecimalNumber(decimal: try XCTUnwrap(result.value)).stringValue
        )
    }

    func testInterestDisplaysGrossValueAndCompactFinalBalance() throws {
        let result = try evaluation("500k TL %40 yıllık 32 gün")

        XCTAssertEqual(result.title, "Simple interest")
        XCTAssertEqual(CalculationPresentation.valueText(result), "17,534.25 TL")
        XCTAssertEqual(CalculationPresentation.detail(result), "Final: 517,534.25 TL · Actual/365")
        let tooltip = CalculationPresentation.tooltip(result)
        XCTAssertTrue(tooltip.contains("Principal: 500,000 TL"))
        XCTAssertTrue(tooltip.contains("Annual rate: 40%"))
        XCTAssertTrue(tooltip.contains("Elapsed days: 32"))
        XCTAssertTrue(tooltip.contains("Year basis: Actual/365"))
        XCTAssertTrue(tooltip.contains("Gross interest: 17,534.24657534 TL"))
        XCTAssertTrue(tooltip.contains("Final balance: 517,534.24657534 TL"))
        XCTAssertTrue(tooltip.contains("Simple interest, no deductions."))
    }

    func testInterestWithoutCurrencyStillUsesTwoDisplayDecimalsAndSelectedBasis() throws {
        let result = try evaluation("1000 at 10% for 32 days basis 360")

        XCTAssertEqual(CalculationPresentation.valueText(result), "8.89")
        XCTAssertEqual(CalculationPresentation.detail(result), "Final: 1,008.89 · Actual/360")
    }

    func testManualDeductionPreservesCurrencyAndProducesCopyableAmount() throws {
        let results = engine.evaluate("interest = 365k TRY %40 yıllık 32 gün\ninterest * .75")
        let result = try XCTUnwrap(results.last)

        XCTAssertEqual(CalculationPresentation.valueText(results[0]), "12,800 TL")
        XCTAssertEqual(CalculationPresentation.valueText(result), "9,600 TL")
        XCTAssertEqual(CalculationPresentation.tooltip(result), "9600 TL")
        XCTAssertEqual(try evaluation(CalculationPresentation.valueText(result)).value, 9_600)
        XCTAssertEqual(try evaluation(CalculationPresentation.valueText(result)).currency, "TRY")
    }

    func testTLAndTRYAliasesAndConversionsPresentAsTL() throws {
        for input in ["1234.567 TL", "1234.567 try", "1234.567 tl", "1234.567 TRY"] {
            XCTAssertEqual(CalculationPresentation.valueText(try evaluation(input)), "1,234.57 TL")
        }
        let result = try XCTUnwrap(engine.evaluate(
            "500 USD to tl", rates: [CurrencyPair(base: "USD", quote: "TRY"): 40]
        ).first)
        XCTAssertEqual(CalculationPresentation.valueText(result), "20,000 TL")
    }

    func testErrorsKeepTitleAndExplainFailure() throws {
        let result = try evaluation("10 / 0")

        XCTAssertEqual(CalculationPresentation.valueText(result), "Calculation error")
        XCTAssertEqual(CalculationPresentation.detail(result), "Cannot divide by zero.")
        XCTAssertEqual(CalculationPresentation.tooltip(result), "Cannot divide by zero.")
    }

    func testUnresolvedConversionUsesItsDescriptionUntilValueExists() throws {
        let result = try evaluation("500 USD to TL")

        XCTAssertNil(result.value)
        XCTAssertEqual(CalculationPresentation.valueText(result), result.title)
        XCTAssertEqual(CalculationPresentation.tooltip(result), result.title)
    }

    func testTinyNonzeroArithmeticNeverDisplaysAsZero() throws {
        let positive = try evaluation("1 / 1000000000000")
        let negative = try evaluation("-1 / 1000000000000")

        XCTAssertEqual(CalculationPresentation.valueText(positive), "0.000000000001")
        XCTAssertEqual(CalculationPresentation.valueText(negative), "-0.000000000001")
        XCTAssertEqual(
            try evaluation(CalculationPresentation.valueText(positive)).value,
            positive.value
        )
        XCTAssertEqual(NumberFormatting.string(0), "0")
        XCTAssertEqual(NumberFormatting.string(try XCTUnwrap(positive.value), maximumFractionDigits: 2), "0")
    }

    private func evaluation(_ input: String) throws -> LineEvaluation {
        try XCTUnwrap(engine.evaluate(input).first, "Missing calculation for \(input)")
    }
}
