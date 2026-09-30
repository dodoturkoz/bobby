import Foundation

enum CheckedDecimalMathError: Error, Equatable {
    case divideByZero
    case outsideRange
}

/// Foundation's decimal multiplication can wrap an out-of-range exponent and
/// report success. Preserve precision while independently checking decimal
/// magnitude, using bounded significands when a raw operation is unsafe.
enum CheckedDecimalMath {
    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard !lhs.isNaN, !rhs.isNaN else { throw CheckedDecimalMathError.outsideRange }
        if lhs == 0 || rhs == 0 { return 0 }
        var left = lhs.significand
        var right = rhs.significand
        var significand = Decimal()
        let status = NSDecimalMultiply(&significand, &left, &right, .plain)
        try check(status, result: significand)
        let value = try scale(significand, by: lhs.exponent + rhs.exponent)
        return (lhs < 0) != (rhs < 0) ? -value : value
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard !lhs.isNaN, !rhs.isNaN else { throw CheckedDecimalMathError.outsideRange }
        guard rhs != 0 else { throw CheckedDecimalMathError.divideByZero }
        if lhs == 0 { return 0 }

        let normalizedLeft = try normalizedSignificand(lhs)
        let normalizedRight = try normalizedSignificand(rhs)
        let power = decimalOrder(lhs) - decimalOrder(rhs)
        let expectedOrder = power + (normalizedLeft < normalizedRight ? -1 : 0)
        guard (-128...165).contains(expectedOrder) else { throw CheckedDecimalMathError.outsideRange }

        // A ratio of normalized significands remains between 0.1 and 10.
        // Align their mantissas to retain useful digits even when an original
        // operand has only one significant digit. Raw division of extreme
        // scales can return a wrong finite answer with the right magnitude.
        var left = normalizedLeft
        var right = normalizedRight
        var leftQuantum = precisionQuantum
        var rightQuantum = precisionQuantum
        try check(NSDecimalNormalize(&left, &leftQuantum, .plain), result: left)
        try check(NSDecimalNormalize(&right, &rightQuantum, .plain), result: right)
        let alignment = NSDecimalNormalize(&left, &right, .plain)
        try check(alignment, result: left)
        try check(alignment, result: right)
        var significand = Decimal()
        let status = NSDecimalDivide(&significand, &left, &right, .plain)
        try check(status, result: significand)
        let value = try scale(significand, by: power)
        return (lhs < 0) != (rhs < 0) ? -value : value
    }

    private static let precisionQuantum = Decimal(sign: .plus, exponent: -37, significand: 1)

    private static func normalizedSignificand(_ value: Decimal) throws -> Decimal {
        var significand = value.significand
        let digits = NSDecimalNumber(decimal: significand).stringValue.count
        var normalized = Decimal()
        let status = NSDecimalMultiplyByPowerOf10(&normalized, &significand, Int16(1 - digits), .plain)
        try check(status, result: normalized)
        return normalized
    }

    private static func check(_ status: Decimal.CalculationError, result: Decimal) throws {
        guard status == .noError || status == .lossOfPrecision, !result.isNaN, result != 0 else {
            throw CheckedDecimalMathError.outsideRange
        }
    }

    private static func scale(_ significand: Decimal, by power: Int) throws -> Decimal {
        let expectedOrder = decimalOrder(significand) + power
        // Decimal's minimum nonzero value is 1e-128. Its largest possible
        // mantissa at exponent 127 has decimal order 165.
        guard (-128...165).contains(expectedOrder), let shortPower = Int16(exactly: power) else {
            throw CheckedDecimalMathError.outsideRange
        }
        var original = significand
        var result = Decimal()
        let status = NSDecimalMultiplyByPowerOf10(&result, &original, shortPower, .plain)
        if (status == .noError || status == .lossOfPrecision),
           !result.isNaN, result != 0, decimalOrder(result) == expectedOrder {
            return result
        }

        // A compact exponent above 127 can still be represented by keeping
        // trailing zeros in the mantissa. Foundation's literal parser handles
        // that representation, whereas its power-of-ten operation rejects it.
        let literal = shiftedLiteral(significand, by: power)
        guard let parsed = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")),
              !parsed.isNaN, parsed != 0, decimalOrder(parsed) == expectedOrder else {
            throw CheckedDecimalMathError.outsideRange
        }
        return parsed
    }

    private static func decimalOrder(_ value: Decimal) -> Int {
        let digits = NSDecimalNumber(decimal: value.significand).stringValue.count
        return value.exponent + digits - 1
    }

    private static func shiftedLiteral(_ value: Decimal, by power: Int) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let digits = parts.joined()
        let point = parts[0].count + power
        if point <= 0 { return "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return digits + String(repeating: "0", count: point - digits.count) }
        let index = digits.index(digits.startIndex, offsetBy: point)
        return String(digits[..<index]) + "." + String(digits[index...])
    }
}
