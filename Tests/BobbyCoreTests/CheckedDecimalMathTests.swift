import Foundation
import XCTest
@testable import BobbyCore

final class CheckedDecimalMathTests: XCTestCase {
    func testOrdinaryMoneyMathRemainsDecimalAndPreservesSigns() throws {
        XCTAssertEqual(try CheckedDecimalMath.multiply(decimal("0.1"), decimal("0.2")), decimal("0.02"))
        XCTAssertEqual(try CheckedDecimalMath.multiply(decimal("-19.99"), 3), decimal("-59.97"))
        XCTAssertEqual(try CheckedDecimalMath.multiply(-2, -3), 6)
        XCTAssertEqual(try CheckedDecimalMath.divide(100, 4), 25)
        XCTAssertEqual(try CheckedDecimalMath.divide(-100, 4), -25)
        XCTAssertEqual(try CheckedDecimalMath.divide(100, -4), -25)
        XCTAssertEqual(try CheckedDecimalMath.divide(-100, -4), 25)
    }

    func testRecurringDivisionAllowsFinitePrecisionLoss() throws {
        let third = try CheckedDecimalMath.divide(1, 3)
        XCTAssertEqual(NumberFormatting.string(third), "0.33333333")
        XCTAssertTrue(third > decimal("0.333333333333333333333333333333333333"))
        XCTAssertTrue(third < decimal("0.333333333333333333333333333333333334"))
    }

    func testLongFractionalDivisorsRetainTheOriginalDecimalPrecision() throws {
        let divisor = decimal("0.12345678901234567890123456789012345678")
        let expected = decimal("8.1000000729000006633900060368490549359")
        XCTAssertEqual(try CheckedDecimalMath.divide(1, divisor), expected)
        let smallExpected = decimal("0.0081000000729000006633900060368490549359")
        XCTAssertEqual(try CheckedDecimalMath.divide(decimal("0.001"), divisor), smallExpected)
        XCTAssertEqual(try CheckedDecimalMath.divide(-1, divisor), -expected)
    }

    func testTinyDivisorsCannotProduceWrongAnswersWithPlausibleMagnitudes() throws {
        XCTAssertEqual(try CheckedDecimalMath.divide(1_000, decimal("123456789e-38")),
                       decimal("810000007371000067076100610392515.55457"))
        XCTAssertEqual(try CheckedDecimalMath.divide(1_000, decimal("999999999e-38")),
                       decimal("1.000000001000000001000000001000000001e32"))
        XCTAssertEqual(try CheckedDecimalMath.divide(1_000, decimal("0.12345678901234567890123456789012345678")),
                       decimal("8100.0000729000006633900060368490549359"))
    }

    func testZeroAmountsRemainZeroAndZeroDenominatorIsDistinct() throws {
        XCTAssertEqual(try CheckedDecimalMath.multiply(0, decimal("1e127")), 0)
        XCTAssertEqual(try CheckedDecimalMath.divide(0, decimal("1e-128")), 0)
        XCTAssertThrowsError(try CheckedDecimalMath.divide(1, 0)) {
            XCTAssertEqual($0 as? CheckedDecimalMathError, .divideByZero)
        }
    }

    func testTheMinimumRepresentableProductCanBeRecoveredFromFactors() throws {
        let minimum = decimal("1e-128")
        XCTAssertEqual(try CheckedDecimalMath.multiply(decimal("2e-128"), decimal("0.5")), minimum)
        XCTAssertEqual(try CheckedDecimalMath.divide(decimal("2e-128"), 2), minimum)
        XCTAssertEqual(try CheckedDecimalMath.multiply(minimum, 10), decimal("1e-127"))
    }

    func testMultiplicationNeverWrapsAnUnderflowIntoAHugeFiniteAnswer() {
        for (left, right) in [(decimal("1e-127"), decimal("1e-10")),
                              (decimal("1e-128"), decimal("1e-128")),
                              (decimal("1e-128"), decimal("0.5"))] {
            XCTAssertThrowsError(try CheckedDecimalMath.multiply(left, right)) {
                XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
            }
        }
    }

    func testDivisionNeverWrapsAnUnderflowIntoAHugeFiniteAnswer() {
        for (left, right) in [(decimal("1e-127"), decimal("1e10")), (decimal("1e-128"), 2)] {
            XCTAssertThrowsError(try CheckedDecimalMath.divide(left, right)) {
                XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
            }
        }
    }

    func testLargeFiniteValuesKeepTheCorrectMagnitude() throws {
        let large = decimal("1" + String(repeating: "0", count: 130))
        XCTAssertEqual(try CheckedDecimalMath.multiply(decimal("1e127"), 1_000), large)
        XCTAssertEqual(try CheckedDecimalMath.multiply(decimal("1e127"), decimal("1e3")), large)
        let quotient = decimal("1" + String(repeating: "0", count: 137))
        XCTAssertEqual(try CheckedDecimalMath.divide(decimal("1e127"), decimal("1e-10")), quotient)
        XCTAssertEqual(try CheckedDecimalMath.divide(quotient, decimal("1e10")), decimal("1e127"))
    }

    func testUnrepresentableLargeResultsReturnRangeErrors() {
        let nearMaximum = decimal("99999999999999999999999999999999999999e127")
        for multiplier: Decimal in [10, 1_000] {
            XCTAssertThrowsError(try CheckedDecimalMath.multiply(nearMaximum, multiplier)) {
                XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
            }
        }
        XCTAssertThrowsError(try CheckedDecimalMath.divide(nearMaximum, decimal("0.001"))) {
            XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
        }
    }

    func testInvalidDecimalOperandsCannotBecomeAnswers() {
        for operation in [CheckedDecimalMath.multiply, CheckedDecimalMath.divide] {
            XCTAssertThrowsError(try operation(.nan, 1)) {
                XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
            }
            XCTAssertThrowsError(try operation(1, .nan)) {
                XCTAssertEqual($0 as? CheckedDecimalMathError, .outsideRange)
            }
        }
    }

    private func decimal(_ literal: String) -> Decimal {
        Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
