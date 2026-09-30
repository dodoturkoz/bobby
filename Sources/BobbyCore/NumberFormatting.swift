import Foundation

/// Consistent English presentation without converting a financial value to Double.
public enum NumberFormatting {
    public static func string(_ value: Decimal, maximumFractionDigits: Int = 8) -> String {
        let fractionDigits = max(0, maximumFractionDigits)
        if fractionDigits >= 8, value != 0, !value.isNaN {
            var original = value
            var rounded = Decimal()
            NSDecimalRound(&rounded, &original, fractionDigits, .plain)
            if rounded == 0 {
                return NSDecimalNumber(decimal: value).stringValue
            }
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }
}
